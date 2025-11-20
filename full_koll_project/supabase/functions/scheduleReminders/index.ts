// deno-lint-ignore-file no-explicit-any
// Schedules and dispatches reminders for receipts, gift cards and subscriptions.
// This function is intended to be executed by Supabase Cron at 05:00 daily.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Json = Record<string, any>;

const ENVIRONMENT = Deno.env.get("ENVIRONMENT") ?? "dev"; // dev | stage | prod
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const NOTIFY_ENDPOINT = Deno.env.get("NOTIFY_ENDPOINT"); // Optional custom push service

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

function isProdLike() {
  return ENVIRONMENT === "prod" || ENVIRONMENT === "stage";
}

function atMidnight(date = new Date()) {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  return d;
}

function addDays(date: Date, days: number) {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return d;
}

async function postNotify(payload: Json) {
  if (!NOTIFY_ENDPOINT) {
    console.log("[REMIND] No NOTIFY_ENDPOINT set; skipping external push", payload);
    return { ok: true };
  }
  const res = await fetch(NOTIFY_ENDPOINT, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const text = await res.text();
    console.error("[REMIND] notify failed", res.status, text);
    return { ok: false, status: res.status, body: text };
  }
  return { ok: true };
}

async function scheduleReceipts(now: Date) {
  // Expect columns: id, owner_id, store, return_deadline, exchange_deadline, warranty_expires, refund_deadline, reminders_enabled
  const from = atMidnight(now);
  const to = addDays(from, 1); // today only; offsets handled below

  const { data: rows, error } = await sb
    .from("receipts")
    .select("id, owner_id, store, return_deadline, exchange_deadline, warranty_expires, refund_deadline, reminders_enabled")
    .neq("archived", true)
    .eq("reminders_enabled", true)
    .or(
      [
        `return_deadline.gte.${from.toISOString()},return_deadline.lt.${to.toISOString()}`,
        `exchange_deadline.gte.${from.toISOString()},exchange_deadline.lt.${to.toISOString()}`,
        `warranty_expires.gte.${from.toISOString()},warranty_expires.lt.${to.toISOString()}`,
        `refund_deadline.gte.${from.toISOString()},refund_deadline.lt.${to.toISOString()}`,
      ].join(",")
    );
  if (error) throw error;

  const notifications: Json[] = [];
  for (const r of rows ?? []) {
    const deadlines: Record<string, string | null> = {
      return_deadline: r.return_deadline,
      exchange_deadline: r.exchange_deadline,
      warranty_expires: r.warranty_expires,
      refund_deadline: r.refund_deadline,
    };
    for (const [key, iso] of Object.entries(deadlines)) {
      if (!iso) continue;
      const d = new Date(iso);
      // Offsets 7 and 1 day before
      for (const offset of [7, 1]) {
        const scheduledAt = atMidnight(addDays(d, -offset));
        if (scheduledAt.toDateString() !== from.toDateString()) continue;
        notifications.push({
          userId: r.owner_id,
          resourceType: "receipt",
          resourceId: r.id,
          titleKey: "notify.receipt.title",
          bodyKey: offset === 1 ? "notify.receipt.body_tomorrow" : "notify.receipt.body_days",
          params: { store: r.store, deadlineType: key, offsetDays: offset },
          title: `Kvitto från ${r.store}`,
          body: offset === 1
            ? `Sista dag för ${key.replace("_", " ")} i morgon.`
            : `Sista dag för ${key.replace("_", " ")} om ${offset} dagar.`,
          scheduledAt: scheduledAt.toISOString(),
          channel: "push",
          data: { deadline: d.toISOString(), deadlineType: key },
        });
      }
    }
  }
  return notifications;
}

async function scheduleGiftCards(now: Date) {
  // Expect columns: id, owner_id, brand, expires_at, reminders_enabled
  const from = atMidnight(now);
  const to = addDays(from, 1);
  const { data: rows, error } = await sb
    .from("giftcards")
    .select("id, owner_id, brand, expires_at, reminders_enabled")
    .eq("reminders_enabled", true)
    .or(
      [
        `expires_at.gte.${from.toISOString()},expires_at.lt.${addDays(from, 30).toISOString()}`,
      ].join(",")
    );
  if (error) throw error;
  const notifications: Json[] = [];
  for (const r of rows ?? []) {
    for (const offset of [30, 7]) {
      const d = r.expires_at ? new Date(r.expires_at) : null;
      if (!d) continue;
      const scheduledAt = atMidnight(addDays(d, -offset));
      if (scheduledAt.toDateString() !== from.toDateString()) continue;
      notifications.push({
        userId: r.owner_id,
        resourceType: "giftcard",
        resourceId: r.id,
        titleKey: "notify.giftcard.title",
        bodyKey: offset === 7 ? "notify.giftcard.body_7" : "notify.giftcard.body_30",
        params: { brand: r.brand, offsetDays: offset },
        title: `Ditt presentkort för ${r.brand} går ut snart!`,
        body: offset === 7 ? "Gäller i 7 dagar till." : "Gäller i 30 dagar till.",
        scheduledAt: scheduledAt.toISOString(),
        channel: "push",
        data: { expiresAt: d.toISOString(), offsetDays: offset },
      });
    }
  }
  return notifications;
}

async function scheduleAutogiro(now: Date) {
  // Expect table: subscriptions/autogiros with next_charge_at, reminder_before_charge_days (array), is_paused, service_name, amount_per_period, currency
  const from = atMidnight(now);
  const to = addDays(from, 1);
  const { data: rows, error } = await sb
    .from("subscriptions")
    .select("id, owner_id, service_name, amount_per_period, currency, next_charge_at, reminder_before_charge_days, is_paused")
    .eq("is_paused", false);
  if (error) throw error;
  const notifications: Json[] = [];
  for (const r of rows ?? []) {
    const days: number[] = Array.isArray(r.reminder_before_charge_days)
      ? r.reminder_before_charge_days
      : [7, 1];
    if (!r.next_charge_at) continue;
    const next = new Date(r.next_charge_at);
    for (const offset of days) {
      const scheduledAt = atMidnight(addDays(next, -offset));
      if (scheduledAt.toDateString() !== from.toDateString()) continue;
      const body = offset === 1
        ? `Påminnelse: ${r.service_name} dras i morgon.`
        : `Autogiro: ${r.service_name} dras ${next.toISOString().substring(0,10)} – belopp ${r.amount_per_period} ${r.currency}`;
      notifications.push({
        userId: r.owner_id,
        resourceType: "autogiro",
        resourceId: r.id,
        titleKey: offset === 1 ? "notify.autogiro.title_tomorrow" : "notify.autogiro.title_date",
        bodyKey: offset === 1 ? "notify.autogiro.body_tomorrow" : "notify.autogiro.body_amount",
        params: { serviceName: r.service_name, chargeDate: next.toISOString().substring(0,10), amount: r.amount_per_period, currency: r.currency, offsetDays: offset },
        title: body,
        body,
        scheduledAt: scheduledAt.toISOString(),
        channel: "push",
        data: { chargeAt: next.toISOString(), offsetDays: offset },
      });
    }
  }
  return notifications;
}

async function handler(req: Request) {
  if (!isProdLike()) {
    return new Response("skipping in dev", { status: 204 });
  }
  try {
    const now = new Date();
    const [a, b, c] = await Promise.all([
      scheduleReceipts(now),
      scheduleGiftCards(now),
      scheduleAutogiro(now),
    ]);
    const notifications = [...a, ...b, ...c];
    console.log(`[REMIND] prepared ${notifications.length} notifications`);

    for (const note of notifications) {
      await postNotify(note);
      // Optional: persist to a log table
      await sb.from("notifications_log").insert({
        user_id: note.userId,
        resource_type: note.resourceType,
        resource_id: note.resourceId,
        title: note.title,
        body: note.body,
        title_key: (note as any).titleKey ?? null,
        body_key: (note as any).bodyKey ?? null,
        params: (note as any).params ?? {},
        scheduled_at: note.scheduledAt,
        channel: note.channel,
        payload: note.data ?? {},
        created_at: new Date().toISOString(),
      });
    }

    return new Response(JSON.stringify({ count: notifications.length }), {
      headers: { "content-type": "application/json" },
    });
  } catch (e) {
    console.error("[REMIND] error", e);
    return new Response("error", { status: 500 });
  }
}

serve(handler);

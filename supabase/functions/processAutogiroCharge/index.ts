// deno-lint-ignore-file no-explicit-any
// Processes due subscription (autogiro) charges and creates budget transactions.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Json = Record<string, any>;

const ENVIRONMENT = Deno.env.get("ENVIRONMENT") ?? "dev"; // dev | stage | prod
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

function isProdLike() {
  return ENVIRONMENT === "prod" || ENVIRONMENT === "stage";
}

function addInterval(date: Date, interval: string) {
  const d = new Date(date);
  switch ((interval || "monthly").toLowerCase()) {
    case "weekly":
      d.setDate(d.getDate() + 7);
      break;
    case "yearly":
      d.setFullYear(d.getFullYear() + 1);
      break;
    case "monthly":
    default:
      d.setMonth(d.getMonth() + 1);
      break;
  }
  return d;
}

async function processCharges(now: Date) {
  // Expect columns: id, owner_id, service_name, amount_per_period, currency, next_charge_at, billing_interval, budget_id, budget_category_id, is_paused
  const { data: due, error } = await sb
    .from("subscriptions")
    .select("id, owner_id, service_name, amount_per_period, currency, next_charge_at, billing_interval, budget_id, budget_category_id, is_paused")
    .lt("next_charge_at", now.toISOString())
    .eq("is_paused", false);
  if (error) throw error;

  let processed = 0;
  for (const s of due ?? []) {
    // Create budget transaction when budget link exists
    if (s.budget_id && s.budget_category_id) {
      await sb.from("transactions").insert({
        budget_id: s.budget_id,
        category_id: s.budget_category_id,
        type: "expense",
        description: s.service_name,
        amount: s.amount_per_period,
        date: new Date().toISOString(),
        source: "subscription",
        source_id: s.id,
      });
    }
    // Bump next charge
    const next = addInterval(new Date(s.next_charge_at), s.billing_interval);
    await sb
      .from("subscriptions")
      .update({ next_charge_at: next.toISOString(), updated_at: new Date().toISOString() })
      .eq("id", s.id);
    processed++;
  }
  return processed;
}

async function handler(_req: Request) {
  if (!isProdLike()) {
    return new Response("skipping in dev", { status: 204 });
  }
  try {
    const count = await processCharges(new Date());
    return new Response(JSON.stringify({ processed: count }), { headers: { "content-type": "application/json" } });
  } catch (e) {
    console.error("[AUTOGIRO] error", e);
    return new Response("error", { status: 500 });
  }
}

serve(handler);

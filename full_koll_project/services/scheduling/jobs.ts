/*
 * Dreamflow daily scheduler entry-point.
 * checkReminders() should be wired to run once per day (00:05) in DF's timer UI.
 *
 * In production the Dreamflow runtime injects database helpers on global.Dreamflow.
 * During local/dev runs we simply log the operations so the Flutter preview
 * can verify the flow in the console.
 */

import { scheduleNotification, cancelNotification } from '../notifications/notifications';

type ReceiptRecord = {
  id: string;
  ownerId: string;
  store: string;
  returnDeadline?: string;
  exchangeDeadline?: string;
  warrantyExpires?: string;
  refundDeadline?: string;
  remindersEnabled?: number | boolean;
  reminderJobs?: Record<string, string[]>;
};

type GiftCardRecord = {
  id: string;
  ownerId: string;
  brand: string;
  expiresAt?: string;
  remindersEnabled?: number | boolean;
  reminderJobIds?: string[];
  currentBalance: number;
};

type AutoGiroRecord = {
  id: string;
  ownerId: string;
  serviceName: string;
  nextChargeAt: string;
  reminderBeforeChargeDays: string;
  isPaused?: number | boolean;
  trialEndsAt?: string;
  reminderOnTrialEnd?: number | boolean;
  chargeReminderJobIds?: string[];
  trialReminderJobId?: string | null;
};

type SettlementRecord = {
  id: string;
  splitGroupId: string;
  payerId: string;
  receiverId: string;
  amount: number;
  status: string;
  createdAt: string;
  reminderJobId?: string | null;
};

const dreamflow = (globalThis as any)?.Dreamflow ?? null;

function log(message: string, data?: unknown) {
  const prefix = '[jobs]';
  if (data) {
    console.log(prefix, message, data);
  } else {
    console.log(prefix, message);
  }
}

function isEnabled(flag?: number | boolean): boolean {
  if (typeof flag === 'boolean') return flag;
  if (typeof flag === 'number') return flag === 1;
  return false;
}

function parseIso(value?: string): Date | null {
  if (!value) return null;
  const parsed = new Date(value);
  // NaN check
  if (Number.isNaN(parsed.getTime())) {
    return null;
  }
  return parsed;
}

function subtractDays(date: Date, days: number): Date {
  const copy = new Date(date);
  copy.setDate(copy.getDate() - days);
  copy.setHours(9, 0, 0, 0);
  return copy;
}

function remindable(date: Date): boolean {
  return date.getTime() > Date.now();
}

async function scheduleReceiptReminders(record: ReceiptRecord) {
  const deadlines: Array<[string, Date]> = [];
  const pairs: Array<[string, string | undefined]> = [
    ['returnDeadline', record.returnDeadline],
    ['exchangeDeadline', record.exchangeDeadline],
    ['warrantyExpires', record.warrantyExpires],
    ['refundDeadline', record.refundDeadline],
  ];

  for (const [key, value] of pairs) {
    const parsed = parseIso(value);
    if (parsed) deadlines.push([key, parsed]);
  }

  if (!deadlines.length) {
    log(`receipt ${record.id} saknar deadlines – avbokar`);
    if (record.reminderJobs) {
      for (const jobIds of Object.values(record.reminderJobs)) {
        for (const id of jobIds) await cancelNotification(id);
      }
    }
    return { reminderJobs: {}, reminder1At: null, reminder2At: null };
  }

  const newJobs: Record<string, string[]> = {};
  const scheduleTimes: Date[] = [];

  log(`⇢ receipt ${record.id} (${record.store})`);

  for (const [kind, deadline] of deadlines) {
    const ids: string[] = [];
    for (const offset of [7, 1]) {
      const scheduled = subtractDays(deadline, offset);
      if (!remindable(scheduled)) continue;
      const jobId = await scheduleNotification(
        record.ownerId,
        scheduled,
        `Kvitto från ${record.store}`,
        `Din rätt att returnera gäller till ${deadline.toLocaleDateString('sv-SE')}.`,
        {
          deadline: deadline.toISOString(),
          deadlineType: kind,
          analyticsEvent: 'receipt_reminder_fired',
        },
      );
      ids.push(jobId);
      scheduleTimes.push(scheduled);
      log('  ↳ receipt_reminder_scheduled', { jobId, kind, scheduled: scheduled.toISOString() });
    }
    if (ids.length) newJobs[kind] = ids;
  }

  scheduleTimes.sort((a, b) => a.getTime() - b.getTime());
  return {
    reminderJobs: newJobs,
    reminder1At: scheduleTimes[0]?.toISOString() ?? null,
    reminder2At: scheduleTimes[1]?.toISOString() ?? null,
  };
}

async function scheduleGiftCardReminders(record: GiftCardRecord) {
  const expiresAt = parseIso(record.expiresAt);
  if (!expiresAt || !isEnabled(record.remindersEnabled)) {
    if (record.reminderJobIds?.length) {
      for (const id of record.reminderJobIds) await cancelNotification(id);
    }
    return { reminderJobIds: [], reminder1At: null, reminder2At: null };
  }

  const ids: string[] = [];
  const times: Date[] = [];

  for (const offset of [30, 7]) {
    const scheduled = subtractDays(expiresAt, offset);
    if (!remindable(scheduled)) continue;
    const jobId = await scheduleNotification(
      record.ownerId,
      scheduled,
      `Ditt presentkort för ${record.brand} går ut snart!`,
      `Saldo: ${Math.round(record.currentBalance)} kr – gäller till ${expiresAt.toLocaleDateString('sv-SE')}.`,
      {
        expiresAt: expiresAt.toISOString(),
        offsetDays: offset,
        analyticsEvent: 'giftcard_reminder_fired',
      },
    );
    ids.push(jobId);
    times.push(scheduled);
    log('  ↳ giftcard_reminder_scheduled', { jobId, offset, scheduled: scheduled.toISOString() });
  }

  times.sort((a, b) => a.getTime() - b.getTime());
  return {
    reminderJobIds: ids,
    reminder1At: times[0]?.toISOString() ?? null,
    reminder2At: times[1]?.toISOString() ?? null,
  };
}

async function scheduleAutoGiroReminders(record: AutoGiroRecord) {
  if (isEnabled(record.isPaused)) {
    if (record.chargeReminderJobIds?.length) {
      for (const id of record.chargeReminderJobIds) await cancelNotification(id);
    }
    if (record.trialReminderJobId) await cancelNotification(record.trialReminderJobId);
    return {
      chargeReminderJobIds: [],
      trialReminderJobId: null,
    };
  }

  const nextCharge = parseIso(record.nextChargeAt);
  if (!nextCharge) return {};

  const chargeIds: string[] = [];

  const offsets = record.reminderBeforeChargeDays
    .split(',')
    .map((n) => parseInt(n, 10))
    .filter((n) => Number.isFinite(n));

  for (const offset of offsets) {
    const scheduled = subtractDays(nextCharge, offset);
    if (!remindable(scheduled)) continue;
    const title = offset === 1
      ? `Påminnelse: ${record.serviceName} dras i morgon.`
      : `Autogiro: ${record.serviceName} dras ${nextCharge.toLocaleDateString('sv-SE')} – belopp ok.`;
    const jobId = await scheduleNotification(
      record.ownerId,
      scheduled,
      title,
      'Belopp: se tjänsten.',
      {
        chargeAt: nextCharge.toISOString(),
        offsetDays: offset,
        analyticsEvent: 'autogiro_reminder_fired',
      },
    );
    chargeIds.push(jobId);
    log('  ↳ autogiro_reminder_scheduled', { jobId, offset, scheduled: scheduled.toISOString() });
  }

  let trialJobId: string | null = null;
  const trialEnds = parseIso(record.trialEndsAt);
  if (trialEnds && isEnabled(record.reminderOnTrialEnd)) {
    if (remindable(trialEnds)) {
      trialJobId = await scheduleNotification(
        record.ownerId,
        subtractDays(trialEnds, 0),
        `Prova-på för ${record.serviceName} slutar snart!`,
        `Prova-på för ${record.serviceName} slutar ${trialEnds.toLocaleDateString('sv-SE')}.`,
        {
          trialEndsAt: trialEnds.toISOString(),
          analyticsEvent: 'autogiro_trial_end',
        },
      );
      log('  ↳ autogiro_trial_end scheduled', { jobId: trialJobId, at: trialEnds.toISOString() });
    }
  }

  return {
    chargeReminderJobIds: chargeIds,
    trialReminderJobId: trialJobId,
  };
}

async function scheduleSplitReminders(record: SettlementRecord) {
  if (record.status === 'settled') {
    if (record.reminderJobId) await cancelNotification(record.reminderJobId);
    return { reminderJobId: null };
  }

  const createdAt = parseIso(record.createdAt);
  if (!createdAt) return {};

  const triggerAt = subtractDays(createdAt, -3); // add 3 days
  const jobId = await scheduleNotification(
    record.payerId,
    triggerAt,
    `Obetald del i ${record.splitGroupId}`,
    `Du är skyldig ${Math.round(record.amount)} kr till ${record.receiverId}.`,
    {
      splitGroupId: record.splitGroupId,
      settlementId: record.id,
      analyticsEvent: 'split_payment_reminder_fired',
    },
  );
  log('  ↳ split_payment_reminder_scheduled', { jobId, settlementId: record.id, at: triggerAt.toISOString() });
  return { reminderJobId: jobId };
}

export async function checkReminders(): Promise<void> {
  const startedAt = new Date();
  log(`checkReminders start ${startedAt.toISOString()}`);

  if (!dreamflow?.database) {
    log('Dreamflow database bridge saknas – kör endast loggexempel.');
    log('exempel: receipt_reminder_scheduled { jobId: "job_demo", scheduled: "2025-01-05T08:00:00Z" }');
    return;
  }

  const db = dreamflow.database;

  const receipts: ReceiptRecord[] = await db.list('receipts', { remindersEnabled: 1 });
  for (const receipt of receipts) {
    if (!isEnabled(receipt.remindersEnabled)) continue;
    const update = await scheduleReceiptReminders(receipt);
    await db.update('receipts', receipt.id, update);
  }

  const giftcards: GiftCardRecord[] = await db.list('giftcards', { remindersEnabled: 1 });
  for (const card of giftcards) {
    const update = await scheduleGiftCardReminders(card);
    await db.update('giftcards', card.id, update);
  }

  const autogiros: AutoGiroRecord[] = await db.list('autogiros');
  for (const giro of autogiros) {
    const update = await scheduleAutoGiroReminders(giro);
    if (Object.keys(update).length) {
      await db.update('autogiros', giro.id, update);
    }
  }

  const settlements: SettlementRecord[] = await db.list('settlements');
  for (const settlement of settlements) {
    const update = await scheduleSplitReminders(settlement);
    if (Object.keys(update).length) {
      await db.update('settlements', settlement.id, update);
    }
  }

  log(`checkReminders done (${new Date().toISOString()})`);
}
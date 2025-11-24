/*
 * Dreamflow serverless helper for Full Koll notification delivery.
 * These helpers run in DF's sandbox where native push/local notifications
 * can be triggered. In dev-mode we simply console.log so the flow is observable.
 */

type NotificationChannel = 'push' | 'local';

interface ScheduledNotification {
  id: string;
  toUserId: string;
  title: string;
  body: string;
  channel: NotificationChannel;
  scheduledAt: Date;
  createdAt: Date;
  data?: Record<string, unknown>;
}

const scheduled = new Map<string, ScheduledNotification>();

const dreamflow = (globalThis as any)?.Dreamflow ?? null;

function log(message: string, payload?: unknown) {
  const prefix = '[notifications]';
  if (payload) {
    console.log(prefix, message, payload);
  } else {
    console.log(prefix, message);
  }
}

function nextId(prefix: string): string {
  if (typeof crypto?.randomUUID === 'function') {
    return `${prefix}_${crypto.randomUUID()}`;
  }
  return `${prefix}_${Date.now()}_${Math.floor(Math.random() * 1_000_000)}`;
}

async function dispatchPush(payload: ScheduledNotification) {
  if (dreamflow?.notifications?.sendPush) {
    await dreamflow.notifications.sendPush({
      toUserId: payload.toUserId,
      title: payload.title,
      body: payload.body,
      data: payload.data ?? {},
    });
    return;
  }

  log(`(dev) PUSH → ${payload.title}`, {
    to: payload.toUserId,
    body: payload.body,
    data: payload.data ?? {},
  });
}

export async function sendPush(
  toUserId: string,
  title: string,
  body: string,
  data: Record<string, unknown> = {},
): Promise<string> {
  const payload: ScheduledNotification = {
    id: nextId('push'),
    toUserId,
    title,
    body,
    channel: 'push',
    scheduledAt: new Date(),
    createdAt: new Date(),
    data,
  };

  await dispatchPush(payload);
  scheduled.set(payload.id, payload);
  return payload.id;
}

export async function scheduleNotification(
  toUserId: string,
  at: Date,
  title: string,
  body: string,
  data: Record<string, unknown> = {},
): Promise<string> {
  const channel: NotificationChannel = 'push';
  const payload: ScheduledNotification = {
    id: nextId('job'),
    toUserId,
    title,
    body,
    channel,
    scheduledAt: at,
    createdAt: new Date(),
    data,
  };

  if (dreamflow?.notifications?.schedule) {
    await dreamflow.notifications.schedule({
      ...payload,
      scheduledAt: at.toISOString(),
    });
  } else {
    log(`(dev) SCHEDULE ${channel.toUpperCase()} @ ${at.toISOString()}`, {
      to: toUserId,
      title,
      data,
    });
  }

  scheduled.set(payload.id, payload);
  return payload.id;
}

export async function cancelNotification(id: string): Promise<void> {
  if (!scheduled.has(id)) {
    log(`(dev) CANCEL skip – okänt jobbid ${id}`);
    return;
  }

  const payload = scheduled.get(id)!;
  if (dreamflow?.notifications?.cancel) {
    await dreamflow.notifications.cancel({ id });
  } else {
    log(`(dev) CANCEL ${id}`, {
      title: payload.title,
      scheduledAt: payload.scheduledAt.toISOString(),
    });
  }

  scheduled.delete(id);
}

export function listScheduled(): ScheduledNotification[] {
  return Array.from(scheduled.values());
}
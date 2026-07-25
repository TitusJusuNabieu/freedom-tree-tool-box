import { prisma } from "@/lib/prisma";
import type { ActivityAction, Prisma, Role } from "@prisma/client";

interface HeaderSource {
  get(name: string): string | null;
}

/** Extracts the originating client IP, accounting for the Caddy reverse proxy. */
export function getClientIp(req: HeaderSource): string | null {
  const forwardedFor = req.get("x-forwarded-for");
  if (forwardedFor) return forwardedFor.split(",")[0]?.trim() || null;
  return req.get("x-real-ip");
}

interface LogActivityInput {
  action: ActivityAction;
  targetType: string;
  targetId?: string | null;
  actorId?: string | null;
  actorName: string;
  actorRole?: Role | null;
  summary: string;
  metadata?: Record<string, unknown>;
  ipAddress?: string | null;
}

/**
 * Records an audit trail entry. Best-effort — a logging failure must never
 * break the request it's describing, so errors are swallowed (and reported
 * to the server console for visibility).
 */
export async function logActivity(input: LogActivityInput): Promise<void> {
  try {
    await prisma.activityLog.create({
      data: {
        action: input.action,
        targetType: input.targetType,
        targetId: input.targetId ?? null,
        actorId: input.actorId ?? null,
        actorName: input.actorName,
        actorRole: input.actorRole ?? null,
        summary: input.summary,
        metadata: (input.metadata ?? undefined) as Prisma.InputJsonValue,
        ipAddress: input.ipAddress ?? null,
      },
    });
  } catch (err) {
    console.error("[activity-log] failed to record activity:", err);
  }
}

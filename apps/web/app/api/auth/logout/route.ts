import { NextRequest, NextResponse } from "next/server";
import { revokeRefreshToken } from "@/lib/auth/jwt";
import { logActivity, getClientIp } from "@/lib/audit/log";

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => null);
  const refreshToken = body?.refreshToken;

  if (typeof refreshToken === "string") {
    const user = await revokeRefreshToken(refreshToken);
    if (user) {
      await logActivity({
        action: "LOGOUT",
        targetType: "Session",
        actorId: user.id,
        actorName: user.name,
        actorRole: user.role,
        summary: `${user.name} logged out (mobile)`,
        ipAddress: getClientIp(req.headers),
      });
    }
  }

  return NextResponse.json({ ok: true });
}

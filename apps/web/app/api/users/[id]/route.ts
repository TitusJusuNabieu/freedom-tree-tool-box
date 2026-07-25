import { NextRequest, NextResponse } from "next/server";
import bcrypt from "bcryptjs";
import { Prisma } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { requireAuth } from "@/lib/auth/requireAuth";
import { logActivity, getClientIp } from "@/lib/audit/log";

const ADMIN_ROLES = new Set(["ADMIN", "SUPER_ADMIN"]);
const PRIVILEGED_ROLES = new Set(["ADMIN", "SUPER_ADMIN"]);

const userSelect = {
  id: true,
  username: true,
  name: true,
  position: true,
  role: true,
  community: true,
  avatarUrl: true,
  active: true,
  createdAt: true,
  updatedAt: true,
} satisfies Prisma.UserSelect;

export async function GET(req: NextRequest, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  const identity = await requireAuth(req);
  if (!identity) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (!ADMIN_ROLES.has(identity.role)) return NextResponse.json({ error: "Forbidden" }, { status: 403 });

  const user = await prisma.user.findUnique({ where: { id }, select: userSelect });
  if (!user) return NextResponse.json({ error: "User not found" }, { status: 404 });

  // ADMIN can only view non-privileged users
  if (identity.role === "ADMIN" && PRIVILEGED_ROLES.has(user.role)) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  return NextResponse.json(user);
}

export async function PUT(req: NextRequest, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  const identity = await requireAuth(req);
  if (!identity) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (!ADMIN_ROLES.has(identity.role)) return NextResponse.json({ error: "Forbidden" }, { status: 403 });

  const target = await prisma.user.findUnique({ where: { id }, select: { role: true, username: true } });
  if (!target) return NextResponse.json({ error: "User not found" }, { status: 404 });

  // ADMIN cannot edit privileged users or assign privileged roles
  if (identity.role === "ADMIN" && PRIVILEGED_ROLES.has(target.role)) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const body = await req.json().catch(() => null);
  if (!body) return NextResponse.json({ error: "Invalid JSON" }, { status: 400 });

  if (body.role && PRIVILEGED_ROLES.has(body.role) && identity.role !== "SUPER_ADMIN") {
    return NextResponse.json({ error: "Forbidden: cannot assign this role" }, { status: 403 });
  }

  const updateData: Prisma.UserUpdateInput = {};
  if (typeof body.name === "string") updateData.name = body.name;
  if (typeof body.position === "string") updateData.position = body.position;
  if (typeof body.role === "string") updateData.role = body.role as Prisma.EnumRoleFieldUpdateOperationsInput["set"];
  if ("community" in body) updateData.community = body.community ?? null;
  if (typeof body.active === "boolean") updateData.active = body.active;
  const passwordReset = typeof body.password === "string" && body.password.length > 0;
  if (passwordReset) {
    updateData.passwordHash = await bcrypt.hash(body.password, 10);
  }

  const user = await prisma.user.update({
    where: { id },
    data: updateData,
    select: userSelect,
  }).catch(() => null);

  if (!user) return NextResponse.json({ error: "User not found" }, { status: 404 });

  const ipAddress = getClientIp(req.headers);
  const roleChanged = typeof body.role === "string" && body.role !== target.role;

  await logActivity({
    action: roleChanged ? "ROLE_CHANGE" : "UPDATE",
    targetType: "User",
    targetId: user.id,
    actorId: identity.userId,
    actorName: identity.name,
    actorRole: identity.role,
    summary: roleChanged
      ? `${identity.name} changed "${target.username}"'s role from ${target.role} to ${user.role}`
      : `${identity.name} updated user "${user.username}"`,
    metadata: roleChanged ? { from: target.role, to: user.role } : undefined,
    ipAddress,
  });

  if (passwordReset) {
    await logActivity({
      action: "PASSWORD_CHANGE",
      targetType: "User",
      targetId: user.id,
      actorId: identity.userId,
      actorName: identity.name,
      actorRole: identity.role,
      summary: `${identity.name} reset the password for "${user.username}"`,
      ipAddress,
    });
  }

  return NextResponse.json(user);
}

export async function PATCH(req: NextRequest, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  const identity = await requireAuth(req);
  if (!identity) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (!ADMIN_ROLES.has(identity.role)) return NextResponse.json({ error: "Forbidden" }, { status: 403 });

  const target = await prisma.user.findUnique({ where: { id }, select: { role: true } });
  if (!target) return NextResponse.json({ error: "User not found" }, { status: 404 });

  if (identity.role === "ADMIN" && PRIVILEGED_ROLES.has(target.role)) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const body = await req.json().catch(() => null);
  if (!body || typeof body.active !== "boolean") {
    return NextResponse.json({ error: "active (boolean) is required" }, { status: 400 });
  }

  const user = await prisma.user.update({
    where: { id },
    data: { active: body.active },
    select: userSelect,
  }).catch(() => null);

  if (!user) return NextResponse.json({ error: "User not found" }, { status: 404 });

  await logActivity({
    action: "STATUS_CHANGE",
    targetType: "User",
    targetId: user.id,
    actorId: identity.userId,
    actorName: identity.name,
    actorRole: identity.role,
    summary: `${identity.name} ${user.active ? "activated" : "deactivated"} user "${user.username}"`,
    metadata: { active: user.active },
    ipAddress: getClientIp(req.headers),
  });

  return NextResponse.json(user);
}

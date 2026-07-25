import { NextRequest, NextResponse } from "next/server";
import bcrypt from "bcryptjs";
import { Prisma } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { requireAuth } from "@/lib/auth/requireAuth";

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

  const target = await prisma.user.findUnique({ where: { id }, select: { role: true } });
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
  if (typeof body.password === "string" && body.password.length > 0) {
    updateData.passwordHash = await bcrypt.hash(body.password, 10);
  }

  const user = await prisma.user.update({
    where: { id },
    data: updateData,
    select: userSelect,
  }).catch(() => null);

  if (!user) return NextResponse.json({ error: "User not found" }, { status: 404 });

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

  return NextResponse.json(user);
}

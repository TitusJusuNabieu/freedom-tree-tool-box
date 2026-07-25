import type { NextAuthOptions } from "next-auth";
import CredentialsProvider from "next-auth/providers/credentials";
import { verifyCredentials } from "@/lib/auth/verifyCredentials";
import { logActivity } from "@/lib/audit/log";

type AppRole = "FIELD_WORKER" | "SUPERVISOR" | "DATA_ANALYST" | "ADMIN" | "SUPER_ADMIN";

/** next-auth's authorize() gets a plain headers object, not a Headers instance. */
function ipFromRawHeaders(headers: Record<string, unknown> | undefined): string | null {
  const raw = headers?.["x-forwarded-for"] ?? headers?.["x-real-ip"];
  if (typeof raw !== "string") return null;
  return raw.split(",")[0]?.trim() || null;
}

export const authOptions: NextAuthOptions = {
  session: { strategy: "jwt" },
  pages: { signIn: "/login" },
  providers: [
    CredentialsProvider({
      name: "Credentials",
      credentials: {
        username: { label: "Username", type: "text" },
        password: { label: "Password", type: "password" },
      },
      async authorize(credentials, req) {
        if (!credentials?.username || !credentials?.password) return null;
        const ipAddress = ipFromRawHeaders(req?.headers as Record<string, unknown> | undefined);

        const user = await verifyCredentials(credentials.username, credentials.password);
        if (!user) {
          await logActivity({
            action: "LOGIN_FAILED",
            targetType: "Session",
            actorName: credentials.username,
            summary: `Failed dashboard login attempt for "${credentials.username}"`,
            ipAddress,
          });
          return null;
        }
        // Field workers use the mobile app only
        if (user.role === "FIELD_WORKER") {
          await logActivity({
            action: "LOGIN_FAILED",
            targetType: "Session",
            actorId: user.id,
            actorName: user.name,
            actorRole: user.role,
            summary: `${user.name} (field worker) attempted dashboard login`,
            ipAddress,
          });
          return null;
        }

        await logActivity({
          action: "LOGIN",
          targetType: "Session",
          actorId: user.id,
          actorName: user.name,
          actorRole: user.role,
          summary: `${user.name} logged in (dashboard)`,
          ipAddress,
        });

        return {
          id: user.id,
          name: user.name,
          role: user.role as AppRole,
          position: user.position,
          community: user.community ?? null,
          avatarUrl: user.avatarUrl ?? null,
        };
      },
    }),
  ],
  events: {
    async signOut({ token }) {
      if (!token?.id) return;
      await logActivity({
        action: "LOGOUT",
        targetType: "Session",
        actorId: token.id as string,
        actorName: (token.name as string | undefined) ?? "Unknown",
        actorRole: token.role as AppRole,
        summary: `${(token.name as string | undefined) ?? "User"} logged out (dashboard)`,
      });
    },
  },
  callbacks: {
    async jwt({ token, user }) {
      if (user) {
        token.id = user.id;
        token.role = user.role;
        token.position = user.position;
        token.community = (user as { community?: string | null }).community ?? null;
        token.avatarUrl = (user as { avatarUrl?: string | null }).avatarUrl ?? null;
      }
      return token;
    },
    async session({ session, token }) {
      if (session.user) {
        session.user.id = token.id as string;
        session.user.role = token.role as AppRole;
        session.user.position = token.position as string;
        session.user.community = (token.community as string | null) ?? null;
        session.user.avatarUrl = (token.avatarUrl as string | null) ?? null;
      }
      return session;
    },
  },
};

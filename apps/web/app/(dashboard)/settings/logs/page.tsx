import { redirect } from "next/navigation";
import { getServerSession } from "next-auth";
import Link from "next/link";
import { Prisma } from "@prisma/client";
import { authOptions } from "@/lib/auth/nextAuthOptions";
import { prisma } from "@/lib/prisma";

const ACTION_COLORS: Record<string, string> = {
  LOGIN: "bg-green-100 text-green-800",
  LOGIN_FAILED: "bg-red-100 text-red-800",
  LOGOUT: "bg-gray-100 text-gray-800",
  CREATE: "bg-blue-100 text-blue-800",
  UPDATE: "bg-indigo-100 text-indigo-800",
  DELETE: "bg-red-100 text-red-800",
  STATUS_CHANGE: "bg-yellow-100 text-yellow-800",
  ROLE_CHANGE: "bg-purple-100 text-purple-800",
  IMPORT: "bg-teal-100 text-teal-800",
  PASSWORD_CHANGE: "bg-orange-100 text-orange-800",
};

const ACTION_LABELS: Record<string, string> = {
  LOGIN: "Login",
  LOGIN_FAILED: "Login failed",
  LOGOUT: "Logout",
  CREATE: "Create",
  UPDATE: "Update",
  DELETE: "Delete",
  STATUS_CHANGE: "Status change",
  ROLE_CHANGE: "Role change",
  IMPORT: "Import",
  PASSWORD_CHANGE: "Password change",
};

const TARGET_TYPES = ["Session", "User", "Profile", "Report", "EducationSurvey", "MaternalHealthSurvey", "ShareLink"];

export default async function ActivityLogPage({
  searchParams,
}: {
  searchParams: { action?: string; targetType?: string; search?: string; page?: string };
}) {
  const session = await getServerSession(authOptions);
  const role = session?.user?.role;
  if (role !== "ADMIN" && role !== "SUPER_ADMIN") redirect("/");

  const page = Math.max(1, parseInt(searchParams.page ?? "1", 10) || 1);
  const pageSize = 30;

  const where: Prisma.ActivityLogWhereInput = {};
  if (searchParams.action) where.action = searchParams.action as never;
  if (searchParams.targetType) where.targetType = searchParams.targetType;
  if (searchParams.search) {
    where.OR = [
      { actorName: { contains: searchParams.search, mode: "insensitive" } },
      { summary: { contains: searchParams.search, mode: "insensitive" } },
    ];
  }

  const [logs, total] = await Promise.all([
    prisma.activityLog.findMany({
      where,
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.activityLog.count({ where }),
  ]);

  const totalPages = Math.ceil(total / pageSize);

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-semibold text-ft-grey-dark">Activity Log</h1>

      {/* Filter bar */}
      <form className="flex flex-wrap gap-3" method="GET">
        <input
          name="search"
          defaultValue={searchParams.search ?? ""}
          placeholder="Search actor or summary…"
          className="rounded-lg border border-ft-grey-light px-3 py-2 text-sm focus:border-ft-orange focus:outline-none"
        />
        <select
          name="action"
          defaultValue={searchParams.action ?? ""}
          className="rounded-lg border border-ft-grey-light px-3 py-2 text-sm focus:border-ft-orange focus:outline-none"
        >
          <option value="">All actions</option>
          {Object.entries(ACTION_LABELS).map(([val, label]) => (
            <option key={val} value={val}>{label}</option>
          ))}
        </select>
        <select
          name="targetType"
          defaultValue={searchParams.targetType ?? ""}
          className="rounded-lg border border-ft-grey-light px-3 py-2 text-sm focus:border-ft-orange focus:outline-none"
        >
          <option value="">All types</option>
          {TARGET_TYPES.map((t) => (
            <option key={t} value={t}>{t}</option>
          ))}
        </select>
        <button
          type="submit"
          className="rounded-lg bg-ft-grey-light px-4 py-2 text-sm font-medium hover:bg-ft-grey-dark hover:text-white"
        >
          Filter
        </button>
      </form>

      {/* Table */}
      <div className="overflow-x-auto rounded-lg border border-ft-grey-light">
        <table className="w-full text-sm">
          <thead className="border-b border-ft-grey-light bg-gray-50">
            <tr>
              <th className="px-4 py-3 text-left font-medium text-ft-grey-dark">When</th>
              <th className="px-4 py-3 text-left font-medium text-ft-grey-dark">Actor</th>
              <th className="px-4 py-3 text-left font-medium text-ft-grey-dark">Action</th>
              <th className="px-4 py-3 text-left font-medium text-ft-grey-dark">Summary</th>
              <th className="px-4 py-3 text-left font-medium text-ft-grey-dark">IP</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-ft-grey-light">
            {logs.map((log) => (
              <tr key={log.id} className="hover:bg-gray-50">
                <td className="whitespace-nowrap px-4 py-3 text-ft-grey-dark">
                  {log.createdAt.toLocaleString()}
                </td>
                <td className="px-4 py-3">
                  <div className="font-medium text-ft-grey-dark">{log.actorName}</div>
                  {log.actorRole && <div className="text-xs text-ft-grey-light">{log.actorRole.replace("_", " ")}</div>}
                </td>
                <td className="px-4 py-3">
                  <span
                    className={`inline-flex rounded-full px-2 py-0.5 text-xs font-semibold ${ACTION_COLORS[log.action] ?? "bg-gray-100 text-gray-800"}`}
                  >
                    {ACTION_LABELS[log.action] ?? log.action}
                  </span>
                </td>
                <td className="px-4 py-3 text-ft-grey-dark">{log.summary}</td>
                <td className="px-4 py-3 text-ft-grey-light">{log.ipAddress ?? "—"}</td>
              </tr>
            ))}
            {logs.length === 0 && (
              <tr>
                <td colSpan={5} className="px-4 py-8 text-center text-ft-grey-light">
                  No activity found.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between text-sm">
          <span className="text-ft-grey-light">
            {total} entries · page {page} of {totalPages}
          </span>
          <div className="flex gap-2">
            {page > 1 && (
              <Link
                href={`?${new URLSearchParams({ ...searchParams, page: String(page - 1) }).toString()}`}
                className="rounded border border-ft-grey-light px-3 py-1 hover:border-ft-orange hover:text-ft-orange"
              >
                Previous
              </Link>
            )}
            {page < totalPages && (
              <Link
                href={`?${new URLSearchParams({ ...searchParams, page: String(page + 1) }).toString()}`}
                className="rounded border border-ft-grey-light px-3 py-1 hover:border-ft-orange hover:text-ft-orange"
              >
                Next
              </Link>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

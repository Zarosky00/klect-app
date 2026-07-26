/**
 * The staff console.
 *
 * Access is gated three times over: `src/middleware.ts` bounces non-staff,
 * `app/(admin)/layout.tsx` redirects them again after resolving `user_roles`,
 * and every `admin_*` RPC re-checks `is_staff()` / `is_admin()` server-side.
 * Only the last one is security — a leaked route reaches a database that
 * refuses it, and every table these views read is behind RLS that says the
 * same thing.
 */
export { AdminDashboard, type AdminDashboardProps } from './AdminDashboard';
export { AdminLoadError } from './AdminLoadError';
export { AuditConsole, type AuditConsoleProps } from './AuditConsole';
export { ContentConsole, type ContentConsoleProps } from './ContentConsole';
export { ReportQueue, type ReportQueueProps } from './ReportQueue';
export { UserConsole, type UserConsoleProps } from './UserConsole';

export {
  MOD_ACTIONS,
  MOD_ACTION_LABELS,
  SUSPENSION_TERMS,
  modActionByHotkey,
  type ModActionSpec,
} from './actions';

export {
  AUDIT_ACTIONS,
  AUDIT_ACTION_LABELS,
  CONTENT_FILTERS,
  CONTENT_FILTER_LABELS,
  EMPTY_REPORT_COUNTS,
  REPORT_STATUSES,
  REPORT_STATUS_LABELS,
  USER_FILTERS,
  USER_FILTER_LABELS,
  auditActionLabel,
  countReportsByStatus,
  describeServerError,
  getAdminUser,
  listAdminContent,
  listAdminUsers,
  listAuditEntries,
  listRolesFor,
  listStaffProfiles,
  sanitiseSearch,
  serverErrorText,
  type AdminContentRow,
  type AdminErrorInfo,
  type AdminPersonRef,
  type AdminUserRow,
  type AuditEntry,
  type ContentVisibilityFilter,
  type ReportCounts,
  type UserFilter,
} from './data';

export { BarList, DayColumns, Sparkline, fillDays, type BarRow, type DayPoint } from './charts';
export { ResolveDialog, type ResolveIntent, type ResolvePayload } from './ResolveDialog';
export { useAdminToast } from './useAdminToast';
export {
  AdminPage,
  Badge,
  Field,
  Kbd,
  KeyboardLegend,
  Notice,
  Panel,
  StatTile,
  TableScroll,
  TimeAgo,
  groupDigits,
  heroFigureClass,
  statValueClass,
  tableClass,
  tdClass,
  thClass,
  type BadgeTone,
  type StatTone,
} from './ui';

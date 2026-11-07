import { z } from "zod";

/**
 * The FlowMate API (v1). Every /v1 call sends `Authorization: Bearer <token>`.
 *
 * Phase 1 syncs the whole workspace as one document (the same JSON the Mac app keeps in
 * workspace.json). The server stores it as is and never reads inside it. `version` grows by one
 * on every write; a write names the version it was based on, so a stale device gets a 409
 * instead of overwriting newer data.
 */

export const Role = z.enum(["owner", "editor", "viewer"]);
export type Role = z.infer<typeof Role>;

export const MeResponse = z.object({
  user: z.object({
    id: z.uuid(),
    email: z.string().nullable(),
    displayName: z.string().nullable(),
  }),
  workspaces: z.array(
    z.object({
      id: z.uuid(),
      name: z.string(),
      role: Role,
      /** null until a device has pushed the first snapshot */
      snapshotVersion: z.number().int().nullable(),
    }),
  ),
});
export type MeResponse = z.infer<typeof MeResponse>;

/** The workspace document. Opaque to the server: any JSON object. */
export const WorkspaceData = z.record(z.string(), z.unknown());

export const SnapshotResponse = z.object({
  version: z.number().int().positive(),
  schemaVersion: z.number().int(),
  updatedAt: z.iso.datetime(),
  updatedByDevice: z.string().nullable(),
  data: WorkspaceData,
});
export type SnapshotResponse = z.infer<typeof SnapshotResponse>;

export const PutSnapshotRequest = z.object({
  /** The version this data was based on; 0 when the workspace has no snapshot yet */
  baseVersion: z.number().int().min(0),
  schemaVersion: z.number().int(),
  deviceName: z.string().max(200).optional(),
  /** Overwrite whatever is there ("Keep this Mac's copy") */
  force: z.boolean().optional(),
  data: WorkspaceData,
});
export type PutSnapshotRequest = z.infer<typeof PutSnapshotRequest>;

export const PutSnapshotResponse = z.object({
  version: z.number().int().positive(),
  updatedAt: z.iso.datetime(),
});
export type PutSnapshotResponse = z.infer<typeof PutSnapshotResponse>;

export const VersionConflict = z.object({
  error: z.literal("version_conflict"),
  currentVersion: z.number().int(),
  updatedAt: z.iso.datetime(),
  updatedByDevice: z.string().nullable(),
});
export type VersionConflict = z.infer<typeof VersionConflict>;

export const ErrorCode = z.enum([
  "unauthorized",
  "forbidden",
  "not_found",
  "no_snapshot",
  "invalid_request",
  "too_large",
  "version_conflict",
  "internal",
]);
export type ErrorCode = z.infer<typeof ErrorCode>;

export const ErrorResponse = z.object({ error: ErrorCode, message: z.string().optional() });
export type ErrorResponse = z.infer<typeof ErrorResponse>;

/** Largest workspace document accepted, in bytes */
export const MAX_SNAPSHOT_BYTES = 25 * 1024 * 1024;

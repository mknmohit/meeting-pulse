-- Keep viewer pairing and daily retention work index-backed as these tables grow.
CREATE INDEX IF NOT EXISTS "viewers_device_active_idx"
  ON "public"."viewers" USING "btree" ("device_id", "created_at", "viewer_user_id")
  WHERE ("revoked_at" IS NULL);

CREATE INDEX IF NOT EXISTS "viewers_active_created_idx"
  ON "public"."viewers" USING "btree" ("created_at")
  WHERE ("revoked_at" IS NULL);

CREATE INDEX IF NOT EXISTS "viewers_revoked_at_idx"
  ON "public"."viewers" USING "btree" ("revoked_at")
  WHERE ("revoked_at" IS NOT NULL);

CREATE INDEX IF NOT EXISTS "pairing_codes_terminal_retention_idx"
  ON "public"."pairing_codes" USING "btree" ((COALESCE("claimed_at", "revoked_at")))
  WHERE ("claimed_at" IS NOT NULL OR "revoked_at" IS NOT NULL);

CREATE INDEX IF NOT EXISTS "pairing_codes_expiry_idx"
  ON "public"."pairing_codes" USING "btree" ("expires_at")
  WHERE (
    "expires_at" IS NOT NULL
    AND "claimed_at" IS NULL
    AND "revoked_at" IS NULL
  );

CREATE INDEX IF NOT EXISTS "pairing_attempts_window_idx"
  ON "public"."pairing_attempts" USING "btree" ("window_started_at");

CREATE INDEX IF NOT EXISTS "devices_revoked_at_idx"
  ON "public"."devices" USING "btree" ("revoked_at")
  WHERE ("revoked_at" IS NOT NULL);

-- This duplicates the unique partial index viewers_one_active_per_viewer.
DROP INDEX IF EXISTS "public"."viewers_viewer_idx";

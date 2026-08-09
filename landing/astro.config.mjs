import sitemap from "@astrojs/sitemap";
import { defineConfig } from "astro/config";

const site = process.env.SITE_URL || "http://localhost:4321";

export default defineConfig({
  site,
  integrations: [sitemap()],
});

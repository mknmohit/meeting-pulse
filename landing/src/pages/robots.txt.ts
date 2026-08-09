import type { APIRoute } from "astro";

export const GET: APIRoute = ({ site }) => {
  const origin = (site?.toString() || "http://localhost:4321").replace(/\/$/, "");
  const body = [
    "User-agent: *",
    "Allow: /",
    "",
    `Sitemap: ${origin}/sitemap-index.xml`,
    "",
  ].join("\n");

  return new Response(body, {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
};

import createMiddleware from "next-intl/middleware";
import { routing } from "@/i18n/routing";

/* Every page lives under [locale], so the matcher has no route exclusions: it
   only skips Next internals, the API and anything with a file extension
   (install.sh, llms.txt, robots.txt, sitemap.xml, icon.svg, images...). */
export default createMiddleware(routing);

export const config = {
  matcher: ["/((?!api|_next|_vercel|.*\\..*).*)"],
};

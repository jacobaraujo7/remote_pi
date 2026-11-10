import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";

/* Pages under /remote-pi belong to the sibling project, so they carry its name
   in the title bar instead of the root layout's "· Cockpit" suffix. */
export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "RemotePiMeta" });
  return {
    title: {
      default: t("titleDefault"),
      template: t("titleTemplate"),
    },
  };
}

export default function RemotePiLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <>{children}</>;
}

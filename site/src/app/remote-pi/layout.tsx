import type { Metadata } from "next";

/* Pages under /remote-pi belong to the sibling project, so they carry its name
   in the title bar instead of the root layout's "· Cockpit" suffix. */
export const metadata: Metadata = {
  title: {
    default: "Remote Pi",
    template: "%s · Remote Pi",
  },
};

export default function RemotePiLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <>{children}</>;
}

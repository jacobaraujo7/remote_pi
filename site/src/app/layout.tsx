import type { Metadata } from "next";
import { Space_Grotesk, Hanken_Grotesk, JetBrains_Mono } from "next/font/google";
import "./globals.css";
import { SiteHeader } from "@/components/header";
import { SiteFooter } from "@/components/footer";

const display = Space_Grotesk({
  variable: "--font-display",
  subsets: ["latin"],
  weight: ["500", "600", "700"],
  display: "swap",
});

const body = Hanken_Grotesk({
  variable: "--font-body",
  subsets: ["latin"],
  weight: ["400", "500", "600"],
  display: "swap",
});

const mono = JetBrains_Mono({
  variable: "--font-mono",
  subsets: ["latin"],
  weight: ["400", "500"],
  display: "swap",
});

const siteTagline =
  "Cockpit: a terminal that grew an IDE around your agents";
const siteDescription =
  "Run Claude Code, Codex, Pi or anything else in real terminals, local or on any machine over SSH, with the viewer, diagnostics, git, worktrees and databases they need to work.";

export const metadata: Metadata = {
  metadataBase: new URL("https://remote-pi.jacobmoura.work"),
  title: {
    default: siteTagline,
    template: "%s · Cockpit",
  },
  description: siteDescription,
  applicationName: "Remote Pi Cockpit",
  authors: [{ name: "Flutterando", url: "https://flutterando.com.br" }],
  keywords: [
    "Cockpit",
    "Remote Pi Cockpit",
    "coding agents",
    "multiplexed terminal",
    "Claude Code",
    "Codex CLI",
    "remote development over SSH",
    "agent IDE",
  ],
  openGraph: {
    type: "website",
    url: "https://remote-pi.jacobmoura.work",
    title: siteTagline,
    description: siteDescription,
    siteName: "Remote Pi Cockpit",
  },
  twitter: {
    card: "summary_large_image",
    title: siteTagline,
    description: siteDescription,
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${display.variable} ${body.variable} ${mono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col bg-bg text-fg">
        <div className="app flex min-h-full flex-1 flex-col" id="top">
          <SiteHeader />
          <main className="flex-1">{children}</main>
          <SiteFooter />
        </div>
      </body>
    </html>
  );
}

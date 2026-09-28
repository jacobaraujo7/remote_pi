import type { NextConfig } from "next";

/* Routes moved in the 2.0 reorganization (plan/63, k32): Cockpit took the root
   and Remote Pi moved under /remote-pi. Every URL that changed place is
   redirected permanently, because these links are published in CHANGELOGs,
   GitHub releases and the apps themselves. */
const MOVED: { from: string; to: string }[] = [
  // Cockpit: up to the root
  { from: "/cockpit", to: "/" },
  { from: "/cockpit/docs", to: "/docs" },
  // Remote Pi: down into its own folder
  { from: "/why", to: "/remote-pi/why" },
  { from: "/tutorials/getting-started", to: "/remote-pi/tutorials/getting-started" },
  { from: "/tutorials/mesh-local", to: "/remote-pi/tutorials/mesh-local" },
  { from: "/tutorials/mesh-remote", to: "/remote-pi/tutorials/mesh-remote" },
  { from: "/tutorials/daemon", to: "/remote-pi/tutorials/daemon" },
  { from: "/tutorials/claude-mesh", to: "/remote-pi/tutorials/claude-mesh" },
];

const nextConfig: NextConfig = {
  output: "standalone",
  async redirects() {
    return [
      // Instalador do cockpit-server: fonte unica no repo
      // (cockpit/install-server.sh); a URL curta do site so redireciona pro
      // raw do GitHub.
      {
        source: "/cockpit-server.sh",
        destination:
          "https://raw.githubusercontent.com/jacobaraujo7/remote_pi/main/cockpit/install-server.sh",
        permanent: false,
      },
      ...MOVED.map(({ from, to }) => ({
        source: from,
        destination: to,
        permanent: true,
      })),
      /* `/docs` and `/tutorials` still exist, now holding Cockpit content, so
         they cannot redirect. The old Remote Pi pages behind them are reachable
         under /remote-pi, linked from both indexes. */
    ];
  },
};

export default nextConfig;

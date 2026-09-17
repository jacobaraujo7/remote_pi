import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  // Instalador do cockpit-server: fonte unica no repo (cockpit/install-server.sh);
  // a URL curta do site so redireciona pro raw do GitHub.
  async redirects() {
    return [
      {
        source: "/cockpit-server.sh",
        destination:
          "https://raw.githubusercontent.com/jacobaraujo7/remote_pi/main/cockpit/install-server.sh",
        permanent: false,
      },
    ];
  },
};

export default nextConfig;

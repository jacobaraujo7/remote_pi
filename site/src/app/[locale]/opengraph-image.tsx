import { ImageResponse } from "next/og";

export const alt = "Remote Pi — Your coding agents, in your pocket";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "row",
          alignItems: "center",
          justifyContent: "center",
          gap: 64,
          backgroundColor: "#000000",
          backgroundImage:
            "radial-gradient(circle at 80% 20%, rgba(79,195,247,0.18), transparent 60%)",
          padding: 80,
          fontFamily: "sans-serif",
        }}
      >
        <div
          style={{
            display: "flex",
            width: 280,
            height: 280,
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <svg width="280" height="280" viewBox="0 0 1024 1024">
            <rect width="1024" height="1024" fill="#000000" rx="200" />
            <rect x="290" y="368" width="444" height="68" rx="10" fill="#FFFFFF" />
            <rect x="345" y="436" width="68" height="320" rx="10" fill="#FFFFFF" />
            <rect x="611" y="436" width="68" height="320" rx="10" fill="#FFFFFF" />
            <circle cx="780" cy="332" r="58" fill="#4FC3F7" />
          </svg>
        </div>
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            gap: 20,
            maxWidth: 640,
          }}
        >
          <div
            style={{
              fontSize: 28,
              color: "#4FC3F7",
              letterSpacing: 4,
              textTransform: "uppercase",
              fontWeight: 600,
            }}
          >
            Remote Pi
          </div>
          <div
            style={{
              fontSize: 64,
              color: "#FFFFFF",
              fontWeight: 700,
              lineHeight: 1.1,
            }}
          >
            Your coding agents, in your pocket.
          </div>
          <div
            style={{
              fontSize: 28,
              color: "#A3A3A3",
              lineHeight: 1.4,
            }}
          >
            Phone gateway · always-on 24/7 · one mesh, any machine
          </div>
        </div>
      </div>
    ),
    { ...size },
  );
}

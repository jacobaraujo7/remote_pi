import { ImageResponse } from "next/og";

export const alt = "Remote Pi Cockpit: Just a terminal. Until your agents need more.";
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
          flexDirection: "column",
          justifyContent: "center",
          gap: 28,
          backgroundColor: "#000000",
          backgroundImage:
            "radial-gradient(circle at 80% 20%, rgba(79,195,247,0.18), transparent 60%)",
          padding: 88,
          fontFamily: "sans-serif",
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
          Remote Pi Cockpit
        </div>
        <div
          style={{
            fontSize: 76,
            color: "#FFFFFF",
            fontWeight: 700,
            lineHeight: 1.08,
            letterSpacing: -2,
            maxWidth: 980,
          }}
        >
          Just a terminal. Until your agents need more.
        </div>
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 16,
            marginTop: 8,
          }}
        >
          <div
            style={{
              display: "flex",
              fontFamily: "monospace",
              fontSize: 30,
              color: "#9ae6b4",
              backgroundColor: "rgba(255,255,255,0.06)",
              border: "1px solid rgba(255,255,255,0.14)",
              borderRadius: 12,
              padding: "14px 24px",
            }}
          >
            $ cockpit · local, no cloud, no account
          </div>
        </div>
      </div>
    ),
    size,
  );
}

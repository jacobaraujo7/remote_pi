import type { Metadata } from "next";
import Link from "next/link";
import { RevealController } from "@/components/landing/reveal-controller";
import { IconAndroid } from "@/components/landing/icons";
import {
  DownloadCard,
  ReleaseNotes,
} from "@/components/download/download-card";
import { loadAppManifest } from "@/lib/app-release";

export const metadata: Metadata = {
  title: "Download the Remote Pi app",
  description:
    "Get the Remote Pi phone app: the direct Android APK with its SHA-256, plus the App Store and Google Play listings.",
};

const PLAY_URL =
  "https://play.google.com/store/apps/details?id=work.jacobmoura.remotepi";
const APP_STORE_URL =
  "https://apps.apple.com/app/remote-pi-coding-agent/id6773499691";

export default async function RemotePiDownloadPage() {
  const app = await loadAppManifest();
  const apk = app.manifest.artifacts[0];

  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <header className="page-head reveal" style={{ maxWidth: 760 }}>
            <span className="eyebrow">Remote Pi · Download</span>
            <h1>Get the Remote Pi app</h1>
            <p className="lede">
              The phone app is the authenticator and the remote control: pair
              once with a QR, then drive your agents from anywhere. Install it
              from a store, or take the APK directly.
            </p>
          </header>

          <section className="dl-product reveal" id="android">
            <div className="section-head">
              <span className="eyebrow">Mobile · Android</span>
              <h2>Remote Pi for Android</h2>
              <p>
                Straight from CI, signed, with a published SHA-256. No Play
                Store account needed.
              </p>
            </div>
            <div className="dl-meta">
              <span>Version {app.manifest.version}</span>
              <span>Released {app.manifest.date}</span>
              <span>Direct APK · signed release</span>
            </div>

            <ReleaseNotes
              version={app.manifest.version}
              notes={app.manifest.notes}
              live={app.live}
            />

            {apk ? (
              <div className="dl-os" id="android-build">
                <div className="dl-os-head">
                  <span className="dl-os-icon">
                    <IconAndroid />
                  </span>
                  <div className="dl-os-titles">
                    <h3>Android</h3>
                    <p>One universal APK for phones and tablets.</p>
                  </div>
                </div>
                <div className="dl-cards dl-cards-solo">
                  <DownloadCard
                    artifact={apk}
                    live={app.live}
                    archLabel="Universal APK"
                    downloadLabel="Download RemotePi.apk"
                  />
                </div>
                <div className="dl-os-help">
                  <div className="dl-note">
                    <ol>
                      <li>
                        Download <code>RemotePi.apk</code> to your phone.
                      </li>
                      <li>Tap the file to start installing.</li>
                      <li>
                        If Android blocks it, allow your browser to{" "}
                        <strong>install unknown apps</strong> when prompted,
                        then continue.
                      </li>
                      <li>
                        Optional: check the <strong>SHA-256</strong> above
                        matches the file before installing.
                      </li>
                    </ol>
                    <p className="dl-note-foot">
                      Prefer a store? Remote Pi is on{" "}
                      <a href={PLAY_URL} target="_blank" rel="noopener noreferrer">
                        Google Play
                      </a>{" "}
                      and on the{" "}
                      <a
                        href={APP_STORE_URL}
                        target="_blank"
                        rel="noopener noreferrer"
                      >
                        App Store
                      </a>
                      .
                    </p>
                  </div>
                </div>
              </div>
            ) : null}

            <div className="dl-foot">
              <p>
                The app drives agents on your machines, so install the{" "}
                <code>remote-pi</code> side first:{" "}
                <Link href="/remote-pi/tutorials/getting-started">
                  the getting started guide
                </Link>{" "}
                goes from a fresh machine to a paired phone. Looking for the
                Cockpit desktop app instead? It has its own{" "}
                <Link href="/download">download page</Link>.
              </p>
            </div>
          </section>
        </div>
      </div>
      <RevealController />
    </div>
  );
}

import { Callout } from "@/components/callout";
import { IconDownload } from "@/components/landing/icons";
import { ShaCopy } from "@/components/download/sha-copy";
import { NotesMarkdown } from "@/components/download/notes-markdown";
import { artifactFileName, formatBytes } from "@/lib/cockpit-release";

/* Shared by the Cockpit downloads (/download) and the Remote Pi app
   (/remote-pi/download): both read the same manifest shape, so both render
   the same card and the same release-notes block. */

/** A download card reads only these fields, so either manifest feeds it. */
export type CardArtifact = {
  format: string;
  arch: string;
  url: string;
  sha256: string;
  size: number;
};

export function DownloadCard({
  artifact,
  live,
  archLabel,
  downloadLabel = "Download",
}: {
  artifact: CardArtifact;
  live: boolean;
  archLabel: string;
  downloadLabel?: string;
}) {
  return (
    <div className="dl-card">
      <div className="dl-card-top">
        <span className="dl-fmt">.{artifact.format}</span>
        <span className="dl-size">{formatBytes(artifact.size)}</span>
      </div>
      <div className="dl-arch">{archLabel}</div>
      <div className="dl-file">{artifactFileName(artifact)}</div>
      {live ? (
        <a className="btn btn-primary dl-btn" href={artifact.url} download>
          <IconDownload /> {downloadLabel}
        </a>
      ) : (
        <span
          className="btn dl-btn dl-btn-off"
          aria-disabled="true"
          title="Not published yet"
        >
          <IconDownload /> Unavailable
        </span>
      )}
      <ShaCopy sha256={artifact.sha256} />
    </div>
  );
}

/** Shared "not published" banner plus release notes for a product band. */
export function ReleaseNotes({
  version,
  notes,
  live,
  releaseUrl,
}: {
  version: string;
  notes: string;
  live: boolean;
  /** Link to the tagged GitHub Release, when the product publishes one. */
  releaseUrl?: string;
}) {
  return (
    <>
      {!live ? (
        <div className="reveal" style={{ marginTop: 24, maxWidth: 760 }}>
          <Callout variant="warning" title="Not published yet">
            <p>
              These builds haven&apos;t been published to the download host yet,
              so the links below aren&apos;t live. The version, size and
              checksum are a preview of the layout, so check back soon.
            </p>
          </Callout>
        </div>
      ) : null}
      {notes ? (
        <div className="reveal" style={{ marginTop: 20, maxWidth: 760 }}>
          <Callout title={`What's new in ${version}`}>
            <NotesMarkdown source={notes} />
            {releaseUrl ? (
              <p className="rn-more">
                <a href={releaseUrl} target="_blank" rel="noopener noreferrer">
                  Full release notes for {version} on GitHub
                </a>
              </p>
            ) : null}
          </Callout>
        </div>
      ) : null}
    </>
  );
}

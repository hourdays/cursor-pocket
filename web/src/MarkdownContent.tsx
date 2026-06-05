import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

export function MarkdownContent({
  text,
  streaming,
}: {
  text: string;
  streaming?: boolean;
}) {
  if (!text) {
    return <>{streaming ? "…" : ""}</>;
  }

  return (
    <ReactMarkdown
      remarkPlugins={[remarkGfm]}
      components={{
        a: ({ href, children }) => (
          <a href={href} target="_blank" rel="noreferrer">
            {children}
          </a>
        ),
        pre: ({ children }) => <pre className="md-pre">{children}</pre>,
        code: ({ className, children }) => {
          const inline = !className;
          if (inline) {
            return <code className="md-code-inline">{children}</code>;
          }
          return <code className={className}>{children}</code>;
        },
      }}
    >
      {text}
    </ReactMarkdown>
  );
}

import * as React from "react";
import { cn } from "@/lib/utils";

/** Minimal Slot: merges props/className into the single child element. */
export function Slot({
  children,
  className,
  ...props
}: React.HTMLAttributes<HTMLElement> & { children?: React.ReactNode }) {
  if (React.isValidElement<{ className?: string }>(children)) {
    return React.cloneElement(children, { ...props, className: cn(className, children.props.className) });
  }
  return <>{children}</>;
}

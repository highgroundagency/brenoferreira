import type * as React from "react";
import { cn } from "@/lib/utils";

export function Label({ className, ...props }: React.LabelHTMLAttributes<HTMLLabelElement>) {
  // biome-ignore lint/a11y/noLabelWithoutControl: primitivo genérico; htmlFor chega via props
  return <label className={cn("text-sm font-medium leading-none", className)} {...props} />;
}

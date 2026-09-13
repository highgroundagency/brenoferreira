"use client";
import { cn } from "@/lib/utils";

export type ChipOption<T extends string> = { value: T; label: string };

type SingleProps<T extends string> = {
  options: ChipOption<T>[];
  value: T | null | undefined;
  onChange: (value: T | null) => void;
  multiple?: false;
  allowEmpty?: boolean;
  name?: string;
  className?: string;
};
type MultiProps<T extends string> = {
  options: ChipOption<T>[];
  value: T[];
  onChange: (value: T[]) => void;
  multiple: true;
  allowEmpty?: boolean;
  name?: string;
  className?: string;
};

/** One-tap chips (single or multiple selection). Large touch targets for field use. */
export function ChipGroup<T extends string>(props: SingleProps<T> | MultiProps<T>) {
  const { options, name, className } = props;
  const isSelected = (v: T) => (props.multiple ? props.value.includes(v) : props.value === v);
  const toggle = (v: T) => {
    if (props.multiple) {
      const next = props.value.includes(v) ? props.value.filter((x) => x !== v) : [...props.value, v];
      props.onChange(next);
    } else {
      props.onChange(props.value === v && props.allowEmpty !== false ? null : v);
    }
  };
  return (
    <fieldset aria-label={name} className={cn("m-0 flex flex-wrap gap-2 border-0 p-0", className)}>
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          aria-pressed={isSelected(o.value)}
          onClick={() => toggle(o.value)}
          className={cn(
            "min-h-11 rounded-full border px-4 py-2 text-sm font-medium transition-colors",
            isSelected(o.value)
              ? "border-primary bg-primary text-primary-foreground"
              : "border-input bg-background hover:bg-accent",
          )}
        >
          {o.label}
        </button>
      ))}
    </fieldset>
  );
}

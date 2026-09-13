"use client";
import { Minus, Plus } from "lucide-react";
import { Button } from "./button";

export function Stepper({
  value,
  onChange,
  min = 0,
  max = 9,
  label,
}: {
  value: number;
  onChange: (v: number) => void;
  min?: number;
  max?: number;
  label?: string;
}) {
  return (
    <fieldset className="m-0 inline-flex items-center gap-3 border-0 p-0" aria-label={label}>
      <Button
        variant="outline"
        size="icon"
        aria-label="menos"
        onClick={() => onChange(Math.max(min, value - 1))}
        disabled={value <= min}
      >
        <Minus className="h-4 w-4" />
      </Button>
      <span className="min-w-6 text-center text-lg font-semibold tabular-nums">{value}</span>
      <Button
        variant="outline"
        size="icon"
        aria-label="mais"
        onClick={() => onChange(Math.min(max, value + 1))}
        disabled={value >= max}
      >
        <Plus className="h-4 w-4" />
      </Button>
    </fieldset>
  );
}

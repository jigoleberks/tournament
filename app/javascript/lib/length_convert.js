// Shared inches<->centimeters conversion for the catch-entry and length-edit
// forms, so the 2.54 factor and the 0.25-grid snap live in exactly one place
// (mirroring LengthHelper::CM_PER_INCH / QUARTER_CM on the server).
export const CM_PER_INCH = 2.54

// Convert a numeric length between units. Same/unknown unit pairs pass through.
export function convertLength(value, fromUnit, toUnit) {
  if (fromUnit === toUnit) return value
  if (fromUnit === "inches" && toUnit === "centimeters") return value * CM_PER_INCH
  if (fromUnit === "centimeters" && toUnit === "inches") return value / CM_PER_INCH
  return value
}

// Snap to the nearest grid step (default the 0.25 unit grid both forms use).
export function snapToGrid(value, step = 0.25) {
  return Math.round(value / step) * step
}

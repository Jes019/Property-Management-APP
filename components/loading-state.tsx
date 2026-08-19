export function LoadingState({ label }: { label: string }) {
  return (
    <div role="status" className="flex min-h-[40vh] items-center justify-center px-6 text-sm text-navy/50">
      {label}
    </div>
  );
}

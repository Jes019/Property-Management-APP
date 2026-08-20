import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

const { signOut, push, refresh } = vi.hoisted(() => ({
  signOut: vi.fn().mockResolvedValue({ error: null }),
  push: vi.fn(),
  refresh: vi.fn(),
}));

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({ auth: { signOut } }),
}));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push, refresh }) }));

import { SignOutButton } from "@/components/sign-out-button";

describe("SignOutButton", () => {
  it("clears the real Supabase Auth session and sends the user to /login, not just a client route change", async () => {
    const user = userEvent.setup();
    render(<SignOutButton />);

    await user.click(screen.getByRole("button", { name: "Sign Out" }));

    expect(signOut).toHaveBeenCalled();
    expect(push).toHaveBeenCalledWith("/login");
    expect(refresh).toHaveBeenCalled();
  });
});

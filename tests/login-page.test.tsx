import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

const { signInWithPassword, isOwner, push, refresh } = vi.hoisted(() => ({
  signInWithPassword: vi.fn().mockResolvedValue({ error: null }),
  isOwner: vi.fn(),
  push: vi.fn(),
  refresh: vi.fn(),
}));

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({ auth: { signInWithPassword } }),
}));
vi.mock("@/lib/data/session", () => ({ isOwner }));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push, refresh }) }));

import LoginPage from "@/app/login/page";

describe("LoginPage post-login routing", () => {
  it("sends an owner-only account (no company role) to /owner, never /dashboard", async () => {
    isOwner.mockResolvedValueOnce(true);
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.type(screen.getByLabelText("Email"), "owner-test@jtc.local");
    await user.type(screen.getByLabelText("Password"), "whatever");
    await user.click(screen.getByRole("button", { name: "Sign In" }));

    await vi.waitFor(() => expect(push).toHaveBeenCalledWith("/owner"));
    expect(push).not.toHaveBeenCalledWith("/dashboard");
  });

  it("sends a company account to /dashboard", async () => {
    isOwner.mockResolvedValueOnce(false);
    const user = userEvent.setup();
    render(<LoginPage />);

    await user.type(screen.getByLabelText("Email"), "admin-test@jtc.local");
    await user.type(screen.getByLabelText("Password"), "whatever");
    await user.click(screen.getByRole("button", { name: "Sign In" }));

    await vi.waitFor(() => expect(push).toHaveBeenCalledWith("/dashboard"));
  });
});

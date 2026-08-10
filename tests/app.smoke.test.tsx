import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import HomePage from "../app/page";

describe("application scaffold", () => {
  it("renders the JTC property platform root page", () => {
    expect(renderToStaticMarkup(createElement(HomePage))).toContain(
      "JTC Property Platform",
    );
  });
});

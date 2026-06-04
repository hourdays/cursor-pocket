import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { DemoWalkthrough } from "./DemoWalkthrough";
import "./styles.css";

const isDemo =
  new URLSearchParams(window.location.search).get("demo") === "1";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    {isDemo ? <DemoWalkthrough /> : <App />}
  </StrictMode>
);

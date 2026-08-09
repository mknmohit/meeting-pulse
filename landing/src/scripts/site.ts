type Theme = "system" | "light" | "dark";

const themeKey = "meeting-pulse-theme";
const root = document.documentElement;
root.classList.add("js");

function systemTheme(): "light" | "dark" {
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

function savedTheme(): Theme {
  try {
    const value = window.localStorage.getItem(themeKey);
    return value === "light" || value === "dark" ? value : "system";
  } catch {
    return "system";
  }
}

function applyTheme(theme: Theme): void {
  const resolved = theme === "system" ? systemTheme() : theme;
  root.dataset.theme = resolved;
  document.querySelectorAll<HTMLElement>("[data-theme-label]").forEach((label) => {
    label.textContent = theme[0].toUpperCase() + theme.slice(1);
  });
  document.querySelectorAll<HTMLButtonElement>("[data-theme-choice]").forEach((choice) => {
    choice.setAttribute("aria-pressed", String(choice.dataset.themeChoice === theme));
  });
  document.querySelectorAll<HTMLImageElement>("[data-theme-image]").forEach((image) => {
    const source = resolved === "dark" ? image.dataset.darkSrc : image.dataset.lightSrc;
    if (source && image.getAttribute("src") !== source) {
      image.src = source;
    }
  });
}

function persistTheme(theme: Theme): void {
  try {
    if (theme === "system") {
      window.localStorage.removeItem(themeKey);
    } else {
      window.localStorage.setItem(themeKey, theme);
    }
  } catch {
    // Theme still applies for this visit when storage is unavailable.
  }
}

applyTheme(savedTheme());

document.querySelectorAll<HTMLButtonElement>("[data-theme-choice]").forEach((choice) => {
  choice.addEventListener("click", () => {
    const next = choice.dataset.themeChoice as Theme | undefined;
    if (!next) return;
    persistTheme(next);
    applyTheme(next);
    choice.closest("details")?.removeAttribute("open");
  });
});

const colorScheme = window.matchMedia("(prefers-color-scheme: dark)");
colorScheme.addEventListener("change", () => {
  if (savedTheme() === "system") applyTheme("system");
});

const menuToggle = document.querySelector<HTMLButtonElement>("[data-menu-toggle]");
const mobileNav = document.querySelector<HTMLElement>("[data-mobile-nav]");

function closeMenu(): void {
  if (!menuToggle || !mobileNav) return;
  menuToggle.setAttribute("aria-expanded", "false");
  mobileNav.hidden = true;
}

menuToggle?.addEventListener("click", () => {
  if (!mobileNav) return;
  const isOpen = menuToggle.getAttribute("aria-expanded") === "true";
  menuToggle.setAttribute("aria-expanded", String(!isOpen));
  mobileNav.hidden = isOpen;
});

mobileNav?.querySelectorAll<HTMLAnchorElement>("[data-menu-link]").forEach((link) => {
  link.addEventListener("click", closeMenu);
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") closeMenu();
});

const year = document.querySelector("[data-year]");
if (year) year.textContent = String(new Date().getFullYear());

const revealItems = document.querySelectorAll<HTMLElement>(".reveal");
if ("IntersectionObserver" in window && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
  const observer = new IntersectionObserver(
    (entries, currentObserver) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        currentObserver.unobserve(entry.target);
      });
    },
    { threshold: 0.12 },
  );
  revealItems.forEach((item) => observer.observe(item));
} else {
  revealItems.forEach((item) => item.classList.add("is-visible"));
}

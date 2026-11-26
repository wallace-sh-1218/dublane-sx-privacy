(() => {
  const reveal = document.querySelectorAll("[data-reveal]");
  if ("IntersectionObserver" in window) {
    // The threshold has to stay tiny. A case page's #steps is several thousand
    // pixels tall, and 8% of it can be taller than the window: on a short
    // window the ratio never reaches the threshold and the whole section stays
    // at opacity 0. One percent is reached as soon as any real part shows.
    const ro = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting) {
            e.target.classList.add("in");
            ro.unobserve(e.target);
          }
        }
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.01 }
    );
    reveal.forEach((el) => ro.observe(el));

    // Safety net: if the callback never fires (restored scroll position, a
    // window that changed size), reveal whatever is already near the viewport.
    // Content must never be permanently invisible.
    window.setTimeout(() => {
      for (const el of reveal) {
        if (el.classList.contains("in")) continue;
        const r = el.getBoundingClientRect();
        if (r.top < window.innerHeight * 1.2 && r.bottom > 0) {
          el.classList.add("in");
          ro.unobserve(el);
        }
      }
    }, 1200);
  } else {
    reveal.forEach((el) => el.classList.add("in"));
  }

  // Pause looping demos that are off screen (saves CPU/battery).
  const vids = document.querySelectorAll("video[data-autoplay]");
  if ("IntersectionObserver" in window) {
    const vo = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          const v = e.target;
          if (e.isIntersecting) {
            const p = v.play();
            if (p && p.catch) p.catch(() => {});
          } else {
            v.pause();
          }
        }
      },
      { threshold: 0.12 }
    );
    vids.forEach((v) => vo.observe(v));
  }

  // Sticky TOC highlight.
  const links = [...document.querySelectorAll("nav.toc a[href^='#']")];
  const map = new Map();
  for (const a of links) {
    const id = a.getAttribute("href").slice(1);
    const sec = document.getElementById(id);
    if (sec) map.set(sec, a);
  }
  if ("IntersectionObserver" in window && map.size) {
    const so = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio);
        if (!visible.length) return;
        links.forEach((l) => l.classList.remove("active"));
        const a = map.get(visible[0].target);
        if (a) a.classList.add("active");
      },
      { rootMargin: "-20% 0px -60% 0px", threshold: [0.05, 0.3, 0.6] }
    );
    map.forEach((_, sec) => so.observe(sec));
  }
})();

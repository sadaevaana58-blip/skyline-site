/**
 * Skyline Client — Interactive Anime.js Engine & Page Transitions
 * High-performance cyberpunk launcher visual effects & physics
 * Powered by Anime.js (v3.2.2)
 */

(function () {
  'use strict';

  const DURATION = 450; // Requested global entrance & reveal duration (450ms)

  // =========================================================================
  // 1. Cyberpunk Page Transitions Engine
  // =========================================================================
  let isTransitioning = false;

  function ensurePageLoader() {
    let loader = document.getElementById('cyberPageLoader');
    if (!loader && document.body) {
      loader = document.createElement('div');
      loader.id = 'cyberPageLoader';
      loader.className = 'cyber-page-loader';
      loader.setAttribute('aria-hidden', 'true');
      document.body.prepend(loader);
    }
    return loader;
  }

  function ensureAmbientGlow() {
    if (document.body && !document.querySelector('.ambient-glow-layer')) {
      const glowLayer = document.createElement('div');
      glowLayer.className = 'ambient-glow-layer';
      glowLayer.setAttribute('aria-hidden', 'true');
      glowLayer.innerHTML = `
        <div class="glow-orb orb-1"></div>
        <div class="glow-orb orb-2"></div>
        <div class="glow-orb orb-3"></div>
      `;
      document.body.prepend(glowLayer);
    }
  }

  function animatePageIn() {
    if (typeof anime === 'undefined') return;

    const loader = ensurePageLoader();
    if (loader) {
      loader.style.opacity = '1';
      anime({
        targets: loader,
        width: ['30%', '100%'],
        opacity: [1, 0],
        duration: DURATION,
        easing: 'easeOutCubic'
      });
    }

    // Smooth entrance for inner pages wrapper
    const innerWrapper = document.querySelector('.legal-page-wrap, .profile-page-wrapper, .admin-page-wrap, .settings-page-wrap, .reset-card-box');
    if (innerWrapper) {
      anime({
        targets: innerWrapper,
        opacity: [0, 1],
        translateY: [15, 0],
        duration: DURATION,
        easing: 'easeOutCubic'
      });
    }
  }

  function navigateWithTransition(url) {
    if (isTransitioning) return;
    if (!url || url.startsWith('#') || url.startsWith('javascript:')) return;

    // Check if target is on same page with hash anchor
    try {
      const targetUrl = new URL(url, window.location.href);
      if (targetUrl.pathname === window.location.pathname && targetUrl.hash) {
        window.location.href = url;
        return;
      }
    } catch (_) {}

    isTransitioning = true;
    const loader = ensurePageLoader();

    if (typeof anime !== 'undefined') {
      if (loader) {
        loader.style.width = '0%';
        loader.style.opacity = '1';
        anime({
          targets: loader,
          width: ['0%', '90%'],
          duration: DURATION,
          easing: 'easeInOutQuad'
        });
      }

      anime({
        targets: 'body',
        opacity: [1, 0],
        duration: Math.round(DURATION * 0.75),
        easing: 'easeInQuad',
        complete: () => {
          window.location.href = url;
        }
      });
    } else {
      window.location.href = url;
    }
  }

  window.navigateWithTransition = navigateWithTransition;

  // Restore page visibility if restored from browser bfcache
  window.addEventListener('pageshow', () => {
    isTransitioning = false;
    document.body.style.opacity = '1';
    document.body.style.transform = 'none';
    const loader = document.getElementById('cyberPageLoader');
    if (loader) {
      loader.style.opacity = '0';
      loader.style.width = '0%';
    }
  });

  // Intercept all internal navigation clicks smoothly
  document.addEventListener('click', (e) => {
    // 1. Check anchor clicks
    const anchor = e.target.closest('a');
    if (anchor) {
      const href = anchor.getAttribute('href');
      const target = anchor.getAttribute('target');
      if (
        href &&
        !href.startsWith('#') &&
        !href.startsWith('mailto:') &&
        !href.startsWith('tel:') &&
        !href.startsWith('javascript:') &&
        target !== '_blank'
      ) {
        // Only internal links
        if (!href.startsWith('http://') && !href.startsWith('https://')) {
          e.preventDefault();
          navigateWithTransition(href);
          return;
        } else {
          try {
            const url = new URL(href, window.location.origin);
            if (url.origin === window.location.origin) {
              e.preventDefault();
              navigateWithTransition(href);
              return;
            }
          } catch (_) {}
        }
      }
    }

    // 2. Check button or element clicks with onclick="location.href='...'"
    const clickable = e.target.closest('[onclick*="location.href"]');
    if (clickable && !clickable.closest('.external-link')) {
      const onclickAttr = clickable.getAttribute('onclick');
      if (onclickAttr) {
        const match = onclickAttr.match(/location\.href\s*=\s*['"]([^'"]+)['"]/);
        if (match && match[1] && !match[1].startsWith('http') && !match[1].startsWith('#')) {
          e.preventDefault();
          e.stopPropagation();
          navigateWithTransition(match[1]);
        }
      }
    }
  }, true);

  // =========================================================================
  // 2. Main Skyline Interactive Animations
  // =========================================================================
  function initSkylineAnimations() {
    if (typeof anime === 'undefined') {
      console.warn('Skyline: anime.js is not loaded.');
      return;
    }

    ensureAmbientGlow();
    ensurePageLoader();
    animatePageIn();

    // Ambient Floating Cyber Plasma Orbs
    const orb1 = document.querySelector('.orb-1');
    const orb2 = document.querySelector('.orb-2');
    const orb3 = document.querySelector('.orb-3');

    if (orb1) {
      anime({
        targets: orb1,
        translateX: () => anime.random(-80, 80),
        translateY: () => anime.random(-60, 60),
        scale: [1, 1.15, 0.95, 1],
        opacity: [0.18, 0.28, 0.18],
        duration: () => anime.random(10000, 14000),
        easing: 'easeInOutSine',
        direction: 'alternate',
        loop: true
      });
    }

    if (orb2) {
      anime({
        targets: orb2,
        translateX: () => anime.random(-90, 70),
        translateY: () => anime.random(-70, 70),
        scale: [1, 1.18, 1],
        opacity: [0.14, 0.24, 0.14],
        duration: () => anime.random(12000, 16000),
        easing: 'easeInOutQuad',
        direction: 'alternate',
        loop: true
      });
    }

    if (orb3) {
      anime({
        targets: orb3,
        translateX: () => anime.random(-70, 100),
        translateY: () => anime.random(-50, 80),
        scale: [0.95, 1.15, 1],
        opacity: [0.15, 0.26, 0.15],
        duration: () => anime.random(11000, 15000),
        easing: 'easeInOutSine',
        direction: 'alternate',
        loop: true
      });
    }

    // =========================================================================
    // 3. Hero Section Cinematic Intro Timeline (index.html)
    // =========================================================================
    const heroSection = document.getElementById('hero');
    if (heroSection) {
      const heroTimeline = anime.timeline({
        easing: 'easeOutExpo'
      });

      heroTimeline
        .add({
          targets: '.site-header',
          translateY: [-16, 0],
          opacity: [0, 1],
          duration: DURATION,
          easing: 'easeOutCubic'
        })
        .add({
          targets: '.hero-title',
          translateY: [22, 0],
          opacity: [0, 1],
          duration: DURATION,
          offset: '-=250'
        })
        .add({
          targets: '.hero-desc',
          translateY: [16, 0],
          opacity: [0, 1],
          duration: DURATION,
          offset: '-=300'
        })
        .add({
          targets: '.hero-actions button',
          translateY: [14, 0],
          scale: [0.95, 1],
          opacity: [0, 1],
          duration: DURATION,
          delay: anime.stagger(45),
          easing: 'easeOutBack(1.2)',
          offset: '-=250'
        })
      if (window.innerWidth >= 768 && document.getElementById('heroCard')) {
        heroTimeline.add({
          targets: '#heroCard',
          translateY: [28, 0],
          scale: [0.96, 1],
          opacity: [0, 1],
          duration: DURATION,
          easing: 'easeOutQuint',
          offset: '-=250'
        });
      }
    }

    // =========================================================================
    // 4. Smooth 3D Mouse Parallax Tilt for Launcher Card (#heroCard)
    // =========================================================================
    const heroCard = document.getElementById('heroCard');
    if (heroCard && window.innerWidth >= 768) {
      let isHovered = false;
      let animationFrame = null;
      let targetRotateX = 0;
      let targetRotateY = 0;
      let currentRotateX = 0;
      let currentRotateY = 0;

      function renderTilt() {
        if (!isHovered) {
          currentRotateX += (0 - currentRotateX) * 0.08;
          currentRotateY += (0 - currentRotateY) * 0.08;
        } else {
          currentRotateX += (targetRotateX - currentRotateX) * 0.12;
          currentRotateY += (targetRotateY - currentRotateY) * 0.12;
        }

        heroCard.style.transform = `perspective(1000px) rotateX(${currentRotateX.toFixed(2)}deg) rotateY(${currentRotateY.toFixed(2)}deg)`;

        if (isHovered || Math.abs(currentRotateX) > 0.01 || Math.abs(currentRotateY) > 0.01) {
          animationFrame = requestAnimationFrame(renderTilt);
        } else {
          heroCard.style.transform = `perspective(1000px) rotateX(0deg) rotateY(0deg)`;
          animationFrame = null;
        }
      }

      window.addEventListener('mousemove', (e) => {
        const rect = heroCard.getBoundingClientRect();
        const heroBounds = heroSection ? heroSection.getBoundingClientRect() : rect;
        if (
          e.clientY >= heroBounds.top - 100 &&
          e.clientY <= heroBounds.bottom + 100 &&
          e.clientX >= 0 &&
          e.clientX <= window.innerWidth
        ) {
          isHovered = true;
          const cardCenterX = rect.left + rect.width / 2;
          const cardCenterY = rect.top + rect.height / 2;
          const deltaX = (e.clientX - cardCenterX) / (window.innerWidth / 2);
          const deltaY = (e.clientY - cardCenterY) / (window.innerHeight / 2);

          targetRotateY = deltaX * 6.5;
          targetRotateX = -deltaY * 5.5;

          if (!animationFrame) {
            animationFrame = requestAnimationFrame(renderTilt);
          }
        } else if (isHovered) {
          isHovered = false;
        }
      });
    }

    // =========================================================================
    // 5. Launcher Play Button Radar Pulse
    // =========================================================================
    const playButtons = document.querySelectorAll('.version-play-btn');
    playButtons.forEach(btn => {
      if (!btn.querySelector('.radar-ring')) {
        const ring = document.createElement('div');
        ring.className = 'radar-ring';
        btn.appendChild(ring);

        anime({
          targets: ring,
          scale: [1, 1.85],
          opacity: [0.85, 0],
          duration: 1900,
          easing: 'easeOutSine',
          loop: true
        });
      }

      anime({
        targets: btn,
        boxShadow: [
          '0 0 10px rgba(34, 197, 94, 0.4)',
          '0 0 20px rgba(34, 197, 94, 0.75)',
          '0 0 10px rgba(34, 197, 94, 0.4)'
        ],
        duration: 2200,
        easing: 'easeInOutSine',
        loop: true
      });
    });

    // =========================================================================
    // 6. Featured Pricing Card Glowing Aura Pulse
    // =========================================================================
    const featuredCard = document.querySelector('.pricing-card.featured');
    if (featuredCard) {
      anime({
        targets: featuredCard,
        boxShadow: [
          '0 0 20px rgba(139, 92, 246, 0.22), inset 0 0 12px rgba(139, 92, 246, 0.08)',
          '0 0 42px rgba(139, 92, 246, 0.50), inset 0 0 22px rgba(139, 92, 246, 0.20)',
          '0 0 20px rgba(139, 92, 246, 0.22), inset 0 0 12px rgba(139, 92, 246, 0.08)'
        ],
        duration: 3400,
        easing: 'easeInOutSine',
        loop: true
      });
    }

    // =========================================================================
    // 7. Intersection Observer Scroll Stagger Animations (duration: 450ms)
    // =========================================================================
    const observerOptions = {
      root: null,
      rootMargin: '0px 0px -20px 0px',
      threshold: 0.08
    };

    const scrollObserver = new IntersectionObserver((entries, observer) => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return;
        const target = entry.target;

        // Features Bento Grid
        if (target.classList.contains('features-grid')) {
          const cards = target.querySelectorAll('.feature-card');
          anime({
            targets: cards,
            translateY: [22, 0],
            opacity: [0, 1],
            scale: [0.97, 1],
            delay: anime.stagger(45),
            duration: DURATION,
            easing: 'easeOutCubic'
          });
          observer.unobserve(target);
        }

        // Versions Showcase
        else if (target.classList.contains('launcher-versions-grid')) {
          const versionCards = target.querySelectorAll('.full-version-card');
          anime({
            targets: versionCards,
            translateY: [24, 0],
            opacity: [0, 1],
            scale: [0.97, 1],
            duration: DURATION,
            easing: 'easeOutExpo'
          });
          observer.unobserve(target);
        }

        // Comparison Container
        else if (target.id === 'comparisonFrame') {
          anime({
            targets: target,
            opacity: [0, 1],
            scale: [0.98, 1],
            duration: DURATION,
            easing: 'easeOutCubic'
          });
          observer.unobserve(target);
        }

        // Pricing Grid & Numeric Counter Animation
        else if (target.classList.contains('pricing-grid')) {
          const pCards = target.querySelectorAll('.pricing-card');
          anime({
            targets: pCards,
            translateY: [24, 0],
            opacity: [0, 1],
            scale: [0.97, 1],
            delay: anime.stagger(50),
            duration: DURATION,
            easing: 'easeOutCubic',
            complete: () => {
              animatePriceCounters();
            }
          });
          observer.unobserve(target);
        }

        // FAQ Items
        else if (target.classList.contains('faq-list')) {
          const faqItems = target.querySelectorAll('.faq-item');
          anime({
            targets: faqItems,
            translateY: [16, 0],
            opacity: [0, 1],
            delay: anime.stagger(40),
            duration: DURATION,
            easing: 'easeOutQuad'
          });
          observer.unobserve(target);
        }
      });
    }, observerOptions);

    // Register elements for scroll reveal
    const featureGrid = document.querySelector('.features-grid');
    if (featureGrid) {
      featureGrid.querySelectorAll('.feature-card').forEach(c => {
        c.style.opacity = '0';
        c.style.transform = 'translateY(22px)';
      });
      scrollObserver.observe(featureGrid);
    }

    const versionGrid = document.querySelector('.launcher-versions-grid');
    if (versionGrid) {
      versionGrid.querySelectorAll('.full-version-card').forEach(c => {
        c.style.opacity = '0';
        c.style.transform = 'translateY(24px)';
      });
      scrollObserver.observe(versionGrid);
    }

    const comparisonFrame = document.getElementById('comparisonFrame');
    if (comparisonFrame) {
      comparisonFrame.style.opacity = '0';
      comparisonFrame.style.transform = 'scale(0.98)';
      scrollObserver.observe(comparisonFrame);
    }

    const pricingGrid = document.querySelector('.pricing-grid');
    if (pricingGrid) {
      pricingGrid.querySelectorAll('.pricing-card').forEach(c => {
        c.style.opacity = '0';
        c.style.transform = 'translateY(24px)';
      });
      scrollObserver.observe(pricingGrid);
    }

    const faqList = document.querySelector('.faq-list');
    if (faqList) {
      faqList.querySelectorAll('.faq-item').forEach(c => {
        c.style.opacity = '0';
        c.style.transform = 'translateY(16px)';
      });
      scrollObserver.observe(faqList);
    }

    // Number Counter for Pricing Amounts (duration: 450ms)
    function animatePriceCounters() {
      const priceEls = document.querySelectorAll('.pricing-amount');
      priceEls.forEach(el => {
        const text = el.textContent || '';
        const match = text.match(/(\d+)/);
        if (match) {
          const targetNum = parseInt(match[1], 10);
          const suffix = text.replace(match[1], '');
          const counterObj = { val: 0 };
          anime({
            targets: counterObj,
            val: targetNum,
            round: 1,
            duration: DURATION,
            easing: 'easeOutExpo',
            update: () => {
              el.textContent = `${counterObj.val}${suffix}`;
            }
          });
        }
      });
    }

    // =========================================================================
    // 8. Other Pages Animation Engine (Profile, Admin, Settings, Legal, Reset)
    // =========================================================================
    // Profile Page
    const profileBoxes = document.querySelectorAll('.profile-card, .profile-admin-box, .auth-modal-card, .profile-download-box, .profile-danger-box');
    if (profileBoxes.length > 0) {
      anime({
        targets: profileBoxes,
        translateY: [20, 0],
        opacity: [0, 1],
        scale: [0.98, 1],
        delay: anime.stagger(50),
        duration: DURATION,
        easing: 'easeOutCubic'
      });
    }

    // Admin Page
    const adminCards = document.querySelectorAll('.admin-card, .stat-card, .admin-users-table-wrap');
    if (adminCards.length > 0) {
      anime({
        targets: adminCards,
        translateY: [20, 0],
        opacity: [0, 1],
        scale: [0.98, 1],
        delay: anime.stagger(45),
        duration: DURATION,
        easing: 'easeOutCubic'
      });
    }

    // Settings Page
    const settingsCards = document.querySelectorAll('.settings-card');
    if (settingsCards.length > 0) {
      anime({
        targets: settingsCards,
        translateY: [20, 0],
        opacity: [0, 1],
        scale: [0.98, 1],
        delay: anime.stagger(50),
        duration: DURATION,
        easing: 'easeOutCubic'
      });
    }

    // Legal Pages (Terms & Privacy)
    const legalCard = document.querySelector('.legal-card');
    if (legalCard) {
      anime({
        targets: legalCard,
        translateY: [24, 0],
        opacity: [0, 1],
        duration: DURATION,
        easing: 'easeOutCubic'
      });
    }

    // Reset Password Page
    const resetBox = document.querySelector('.reset-card-box');
    if (resetBox) {
      anime({
        targets: resetBox,
        translateY: [24, 0],
        opacity: [0, 1],
        scale: [0.98, 1],
        duration: DURATION,
        easing: 'easeOutCubic'
      });
    }

    // =========================================================================
    // 9. Interactive Micro-Physics: Hover Spring & Button Elastic Clicks
    // =========================================================================
    // Feature Card Icon Hover Bounce
    document.querySelectorAll('.feature-card').forEach(card => {
      const iconBox = card.querySelector('.feature-icon-box');
      if (iconBox) {
        card.addEventListener('mouseenter', () => {
          anime({
            targets: iconBox,
            scale: [1, 1.22, 1],
            rotate: [-6, 6, 0],
            duration: 500,
            easing: 'easeOutElastic(1, 0.4)'
          });
        });
      }
    });

    // Button Elastic Tactile Feedback
    document.querySelectorAll('.btn-fill, .btn-outline, .btn-ghost, .page-back-btn').forEach(btn => {
      btn.addEventListener('mousedown', () => {
        anime({
          targets: btn,
          scale: 0.94,
          duration: 120,
          easing: 'easeOutQuad'
        });
      });
      btn.addEventListener('mouseup', () => {
        anime({
          targets: btn,
          scale: 1,
          duration: 350,
          easing: 'easeOutElastic(1.4, 0.5)'
        });
      });
      btn.addEventListener('mouseleave', () => {
        anime({
          targets: btn,
          scale: 1,
          duration: 180,
          easing: 'easeOutQuad'
        });
      });
    });
  }

  // Run when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initSkylineAnimations);
  } else {
    initSkylineAnimations();
  }
})();

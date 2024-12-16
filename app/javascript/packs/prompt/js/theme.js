// theme.js

import AOS from 'aos';
import Swiper from 'swiper';

function initTheme() {
  function normalizarUrl(url) {
    const base = window.location.origin;
    const u = new URL(url, base);
    u.hash = '';
    u.search = '';
    u.pathname = u.pathname.replace(/index\.html$/, '');
    if (u.pathname === '') u.pathname = '/';
    return u.toString();
  }

  const paginaAtual = normalizarUrl(window.location.href);

  function marcarLinkAtivoMenuPrincipal() {
    const links = document.querySelectorAll('#navbar .navbar-nav a');
    links.forEach(link => {
      const hrefNormalizado = normalizarUrl(link.getAttribute('href') || '');
      if (hrefNormalizado === paginaAtual) {
        link.classList.add('active');
        let parent = link.parentElement;
        for (let i = 0; i < 5; i++) {
          if (!parent) break;
          if (parent.classList?.contains('nav-item')) {
            const dropdown = parent.querySelector('[data-fc-type="dropdown"]');
            if (dropdown) dropdown.classList.add('active');
          }
          parent = parent.parentElement;
        }
      }
    });
  }

  function marcarLinkAtivoMenuMobile() {
    const links = document.querySelectorAll('#mobileMenu .navbar-nav a');
    links.forEach(link => {
      const hrefNormalizado = normalizarUrl(link.getAttribute('href') || '');
      if (hrefNormalizado === paginaAtual) {
        link.classList.add('active');
        const navItem = link.closest('.nav-item');
        if (navItem) {
          const collapseElement = navItem.querySelector('[data-fc-type="collapse"]');
          if (collapseElement) {
            collapseElement.classList.add('active');
            if (window.frost && frost.Collapse) {
              const collapse = frost.Collapse.getInstanceOrCreate(collapseElement);
              collapse.show();
              const parentCollapse = link.parentElement?.parentElement;
              if (parentCollapse && parentCollapse.style) {
                parentCollapse.style.height = null;
              }
            }
          }
        }
      }
    });
  }

  function ativarStickyNav() {
    const navbar = document.getElementById('navbar');
    if (!navbar) return;
    function verificarScroll() {
      const scrollPos = document.documentElement.scrollTop || document.body.scrollTop;
      if (scrollPos >= 75) {
        navbar.classList.add('nav-sticky');
      } else {
        navbar.classList.remove('nav-sticky');
      }
    }
    window.addEventListener('scroll', verificarScroll);
    verificarScroll();
  }

  function initBackToTop() {
    const btn = document.querySelector('[data-toggle="back-to-top"]');
    if (!btn) return;
    function verificarScrollTop() {
      if (window.pageYOffset > 72) {
        btn.classList.remove('hidden');
        btn.classList.add('flex');
      } else {
        btn.classList.remove('flex');
        btn.classList.add('hidden');
      }
    }
    window.addEventListener('scroll', verificarScrollTop);
    verificarScrollTop();

    btn.addEventListener('click', (e) => {
      e.preventDefault();
      window.scrollTo({ top: 0, behavior: 'smooth' });
    });
  }

  function initAOS() {
    AOS.init();
  }

  function initSwipers() {
    if (document.querySelector('#swiper_one')) {
      new Swiper('#swiper_one', {
        slidesPerView: 1,
        spaceBetween: 30,
        loop: true,
        autoplay: { delay: 2500, disableOnInteraction: false },
        pagination: { el: '.swiper-pagination', clickable: true },
        rewind: true,
        navigation: { nextEl: '.button-next', prevEl: '.button-prev' },
      });
    }
    if (document.querySelector('#swiper_two')) {
      new Swiper('#swiper_two', {
        slidesPerView: 1,
        loop: true,
        autoHeight: true,
        spaceBetween: 30,
        navigation: { nextEl: '.button-next', prevEl: '.button-prev' },
        breakpoints: {
          768: { slidesPerView: 2 },
        },
      });
    }
  }

  function initTypewriter() {
    class Typewriter {
      constructor(el, words, period) {
        this.el = el;
        this.words = words;
        this.period = period || 2000;
        this.txt = '';
        this.loopNum = 0;
        this.isDeleting = false;
        this.tick();
      }
      tick() {
        const i = this.loopNum % this.words.length;
        const fullTxt = this.words[i];
        if (this.isDeleting) {
          this.txt = fullTxt.substring(0, this.txt.length - 1);
        } else {
          this.txt = fullTxt.substring(0, this.txt.length + 1);
        }
        this.el.innerHTML = `<span class="wrap">${this.txt}</span>`;
        let delta = 200 - Math.random() * 100;
        if (this.isDeleting) delta /= 2;
        if (!this.isDeleting && this.txt === fullTxt) {
          delta = this.period;
          this.isDeleting = true;
        } else if (this.isDeleting && this.txt === '') {
          this.isDeleting = false;
          this.loopNum++;
          delta = 500;
        }
        setTimeout(() => this.tick(), delta);
      }
    }

    const elements = document.querySelectorAll('.typewrite');
    elements.forEach(el => {
      const dataType = el.getAttribute('data-type');
      const dataPeriod = el.getAttribute('data-period');
      if (dataType) {
        const words = JSON.parse(dataType);
        new Typewriter(el, words, parseInt(dataPeriod, 10));
      }
    });
  }

  // Execução de todas as funções
  initAOS();
  marcarLinkAtivoMenuPrincipal();
  marcarLinkAtivoMenuMobile();
  ativarStickyNav();
  initBackToTop();
  initSwipers();
  initTypewriter();
}

// Exporta a função initTheme, sem listener do DOM
export { initTheme };

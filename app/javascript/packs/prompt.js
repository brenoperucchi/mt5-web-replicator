// prompt.js

import "@frostui/tailwindcss"
import "packs/prompt.scss";
import 'alpinejs'; 
import 'flowbite'; 

import Rails from '@rails/ujs';
import Turbolinks from 'turbolinks';
import * as ActiveStorage from '@rails/activestorage';
// Rails.start();
// Turbolinks.start();
// Inicializando bibliotecas do Rails
Rails.start();
Turbolinks.start();
ActiveStorage.start();

import GLightbox from 'glightbox';
import Shuffle from 'shufflejs';

import { initTheme } from "./prompt/js/theme.js";  // <-- Importa a função

document.addEventListener('turbolinks:load', () => {
  // Inicializando bibliotecas do Rails
  // AOS, GLightbox, ShuffleJS, etc...
  // AOS.init();

  const lightbox = GLightbox({ /* options */ });

  const element = document.querySelector('.my-grid');
  if (element) {
    const shuffleInstance = new Shuffle(element, {
      itemSelector: '.grid-item',
      sizer: '.my-sizer-element',
    });
  }

  // Swiper e comportamento do theme.js
  initTheme();  // <-- Chamamos a função que faz tudo do theme.js
});

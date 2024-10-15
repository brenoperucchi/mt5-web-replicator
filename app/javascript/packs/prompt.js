import "packs/prompt.scss";
import 'alpinejs'; // Importar o Alpine.js antes
import 'flowbite'; // Importar o Flowbite após o Alpine.js

// Inicialização das bibliotecas
document.addEventListener('turbolinks:load', () => {
  Rails.start();
  Turbolinks.start();
  ActiveStorage.start();

  AOS.init();

  // Inicialização do GLightbox
  const lightbox = GLightbox({
    // opções
  });

  // Inicialização do ShuffleJS
  const element = document.querySelector('.my-grid');
  if (element) {
    const shuffleInstance = new Shuffle(element, {
      itemSelector: '.grid-item',
      sizer: '.my-sizer-element',
    });
  }

  // Inicialize o Swiper conforme necessário
});

// Importação dos seus arquivos locais (se necessário)
import "./prompt/js/gallery.js";
import "./prompt/js/theme.js";

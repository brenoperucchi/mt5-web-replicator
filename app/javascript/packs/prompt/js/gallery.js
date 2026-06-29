// app/javascript/packs/prompt/js/gallery.js

import GLightbox from 'glightbox';
import Shuffle from 'shufflejs';

/*
Template Name: Prompt - Tailwind CSS Multipurpose Landing Page Template
Version: 1.1.0
Author: coderthemes
Email: support@coderthemes.com
*/

function init() {
    // Remova a linha abaixo, pois ela sobrescreve o Shuffle importado com uma referência possivelmente indefinida
    // const Shuffle = window.Shuffle;

    class Demo {
        constructor(element) {
            this.element = element;
            this.shuffle = new Shuffle(element, {
                itemSelector: '.picture-item'
            });

            this.activeFilters = [];
            this.addFilterButtons();
        }

        addFilterButtons() {
            const options = document.querySelector('.filter-options');
            if (!options) {
                return;
            }

            const filterButtons = Array.from(options.children);
            const onClick = this.handleFilterClick.bind(this);
            filterButtons.forEach((button) => {
                button.addEventListener('click', onClick, false);
            });
        }

        handleFilterClick(evt) {
            const button = evt.currentTarget;
            const isActive = button.classList.contains('active');
            const buttonGroup = button.getAttribute('data-group');

            this.removeActiveClassFromChildren(button.parentNode);

            button.classList.add('active');
            this.shuffle.filter(buttonGroup);
        }

        removeActiveClassFromChildren(parent) {
            const { children } = parent;
            for (let i = children.length - 1; i >= 0; i--) {
                children[i].classList.remove('active');
            }
        }
    }

    // Use 'turbolinks:load' se estiver usando o Turbolinks
    document.addEventListener('turbolinks:load', () => {
        const galleryElement = document.getElementById('gallery-wrapper');
        if (galleryElement) {
            window.demo = new Demo(galleryElement);
        }
    });

    // GLightbox Popup
    const lightbox = GLightbox({
        selector: '.image-popup',
        title: false,
    });
}

init();

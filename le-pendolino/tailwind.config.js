/** Configuration Tailwind du site Le Pendolino.
 *  Après modification de index.html, régénérer la feuille de style :
 *  npx tailwindcss@3.4.17 -i src/input.css -o css/style.css --minify
 */
module.exports = {
  content: ['./*.html', './js/*.js'],
  theme: {
    extend: {
      colors: {
        cream: { DEFAULT: '#FAF7F2', deep: '#F2E8D8' },
        mozza: '#FFFDF8',
        tomato: { DEFAULT: '#C8322B', dark: '#A42720', soft: '#E9867E' },
        basil: { DEFAULT: '#1E3A2B', light: '#2C5140', deep: '#14281D' },
        charcoal: '#1A1A1A',
        copper: { DEFAULT: '#D4A373', dark: '#8C5E34', light: '#EBCBA6' },
      },
      fontFamily: {
        display: ['"Playfair Display"', 'Georgia', '"Times New Roman"', 'serif'],
        sans: ['"Plus Jakarta Sans"', 'system-ui', '-apple-system', '"Segoe UI"', 'sans-serif'],
        hand: ['Caveat', '"Segoe Print"', '"Bradley Hand"', 'cursive'],
        script: ['"Kaushan Script"', 'Caveat', 'cursive'],
        board: ['Oswald', '"Arial Narrow"', 'Impact', 'sans-serif'],
      },
    },
  },
  plugins: [],
};

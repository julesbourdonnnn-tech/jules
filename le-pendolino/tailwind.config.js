/** Configuration Tailwind du site Le Pendolino.
 *  Après modification de index.html, régénérer la feuille de style :
 *  npx tailwindcss@3.4.17 -i src/input.css -o css/style.css --minify
 */
module.exports = {
  content: ['./*.html', './js/*.js'],
  theme: {
    extend: {
      colors: {
        cream: { DEFAULT: '#FAF7F2', dark: '#F1EBE1' },
        tomato: { DEFAULT: '#C8322B', dark: '#A42720' },
        basil: { DEFAULT: '#1E3A2B', light: '#2A4D3A' },
        charcoal: '#1A1A1A',
        copper: { DEFAULT: '#D4A373', dark: '#8C5E34' },
      },
      fontFamily: {
        display: ['"Playfair Display"', 'Georgia', 'serif'],
        sans: ['"Plus Jakarta Sans"', 'system-ui', '-apple-system', 'Segoe UI', 'sans-serif'],
      },
      boxShadow: {
        card: '0 1px 2px rgba(26,26,26,.04), 0 8px 24px -12px rgba(26,26,26,.12)',
        lift: '0 2px 4px rgba(26,26,26,.05), 0 24px 48px -16px rgba(30,58,43,.28)',
      },
      keyframes: {
        'fade-up': { '0%': { opacity: 0, transform: 'translateY(16px)' }, '100%': { opacity: 1, transform: 'none' } },
      },
      animation: { 'fade-up': 'fade-up .9s cubic-bezier(.2,.7,.2,1) both' },
    },
  },
  plugins: [],
};

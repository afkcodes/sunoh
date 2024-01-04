/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        // Dark mode backgrounds
        bgPrimary: '#121212',
        bgSecondary: '#1E1E1E',
        bgTertiary: '#292929',

        // Text colors
        textLight: '#FFFFFF',
        textMedium: '#CCCCCC',
        textDark: '#333333',
        textAccent: '#FF6B81',

        // Accent colors
        accentPrimary: '#B73B4A', // Slightly darker primary accent color

        // Error/Warning colors
        error: '#FF6347',
        warning: '#FFA500',

        // Call to Action (CTA) colors
        ctaPrimary: '#33B786',
        ctaHover: '#1E996D',
        ctaActive: '#008254',

        // Primary Button colors
        btnPrimary: '#B73B4A', // Updated primary button color
        btnPrimaryHover: '#A1303F', // Slightly darker hover color
        btnPrimaryActive: '#902731', // Slightly darker active color

        // Secondary Button colors
        btnSecondary: '#33B786',
        btnSecondaryHover: '#1E996D',
        btnSecondaryActive: '#008254',

        // Outline Button colors
        btnOutlineText: '#FFFFFF',
        btnOutlineBorder: '#FFFFFF',
        btnOutlineHoverText: '#333333',
        btnOutlineHoverBorder: '#333333',

        // Dark mode button colors
        btnDark: '#252525',
        btnDarkHover: '#383838',
        btnDarkActive: '#1F1F1F',

        // Ghost Button colors
        btnGhostBg: 'transparent',
        btnGhostBorder: '#FFFFFF',
        btnGhostHoverBg: 'rgba(255, 255, 255, 0.1)',
        btnGhostActiveBg: 'rgba(255, 255, 255, 0.2)',
        btnGhostHoverBorder: '#FFFFFF',
        btnGhostActiveBorder: '#FFFFFF',

        // Link colors
        link: '#58A6FF',
        linkHover: '#448EFF',
        linkActive: '#2354CC',

        // Disabled state
        disabled: '#666666'
      },
      boxShadow: {
        'elevation-1': '0 2px 4px 0 rgba(0, 0, 0, 0.10)',
        'elevation-2': '0 4px 8px 0 rgba(0, 0, 0, 0.12)',
        'elevation-3': '0 8px 16px 0 rgba(0, 0, 0, 0.14)'
      }
    }
  },
  plugins: []
};

/** Public build-time identity; never put API secrets in VITE_ variables. */
export const appBrand = {
  name: import.meta.env.VITE_APP_NAME?.trim() || 'Hoppa',
  logo: import.meta.env.VITE_APP_LOGO?.trim() || '/hoppa-icon.png',
};

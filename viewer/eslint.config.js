import astro from 'eslint-plugin-astro';

export default [
  {
    ignores: ['dist/**', '.astro/**'],
  },
  ...astro.configs['flat/recommended'],
];

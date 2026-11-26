/**
 * Configuration Jest — via le preset officiel Next.js (`next/jest`), qui charge
 * SWC, les alias de `tsconfig.json` et les variables d'environnement.
 *
 * Avant cette configuration, `npm test` n'exécutait rien : le seul fichier de
 * test du projet était ignoré faute de transform TSX (Jest échouait sur
 * `Unexpected token, expected ","`).
 */
const nextJest = require('next/jest');

const createJestConfig = nextJest({ dir: './' });

/** @type {import('jest').Config} */
const config = {
  testEnvironment: 'jest-environment-jsdom',
  setupFilesAfterEnv: ['<rootDir>/jest.setup.ts'],
  testMatch: ['**/__tests__/**/*.test.[jt]s?(x)'],
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/$1',
  },
  testPathIgnorePatterns: ['/node_modules/', '/.next/', '/out/', '/cypress/'],
  collectCoverageFrom: [
    'lib/**/*.{ts,tsx}',
    'hooks/**/*.{ts,tsx}',
    'stores/**/*.{ts,tsx}',
    '!**/*.d.ts',
  ],
};

module.exports = createJestConfig(config);

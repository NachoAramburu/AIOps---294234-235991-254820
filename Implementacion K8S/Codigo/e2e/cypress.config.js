// Cypress + Cucumber (C22). La URL base sale de CYPRESS_BASE_URL:
//   @smoke: el build de Angular servido en local (http://localhost:4200), con la API simulada.
//   @e2e:   la app real en el cluster por el Ingress (http://127.0.0.1, con minikube tunnel).
const { defineConfig } = require("cypress");
const createBundler = require("@bahmutov/cypress-esbuild-preprocessor");
const { addCucumberPreprocessorPlugin } = require("@badeball/cypress-cucumber-preprocessor");
const { createEsbuildPlugin } = require("@badeball/cypress-cucumber-preprocessor/esbuild");

module.exports = defineConfig({
  e2e: {
    baseUrl: process.env.CYPRESS_BASE_URL || "http://localhost:4200",
    specPattern: "cypress/e2e/**/*.feature",
    supportFile: false,
    video: false,
    async setupNodeEvents(on, config) {
      await addCucumberPreprocessorPlugin(on, config);
      on("file:preprocessor", createBundler({ plugins: [createEsbuildPlugin(config)] }));
      return config;
    },
  },
});

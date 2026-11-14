import { Given, When, Then } from "@badeball/cypress-cucumber-preprocessor";

// Bug conocido de la app, no de esta prueba: con credenciales inválidas, login.service devuelve un resultado vacío
// y LoginComponent igual lee login.userName, lo que lanza un TypeError en el navegador. La pantalla se comporta bien
// (muestra el aviso y se queda en el login), así que se ignora solo ese error puntual. Ver docs/bdd.md.
Cypress.on("uncaught:exception", (err) => {
  if (err.message.includes("reading 'userName'")) {
    return false;
  }
  return true;
});

// ---------- API simulada (escenarios @smoke) ----------

Given("que la API acepta el login como administrador", () => {
  cy.intercept("GET", "**/api/**", { statusCode: 200, body: [] });
  cy.intercept("POST", "**/api/login", {
    statusCode: 200,
    body: { token: "00000000-0000-0000-0000-000000000001", role: "Administrator", userName: "admin" },
  }).as("login");
});

Given("que la API rechaza el login", () => {
  cy.intercept("GET", "**/api/**", { statusCode: 200, body: [] });
  cy.intercept("POST", "**/api/login", {
    statusCode: 400,
    body: { message: "Invalid username or password" },
  }).as("login");
});

// ---------- Pantalla de login (los dos tipos de escenario) ----------

When("abro la pantalla de login", () => {
  cy.visit("/login");
});

When("ingreso el usuario {string} y la contraseña {string}", (usuario, clave) => {
  cy.get('input[placeholder="Username"]').clear().type(usuario);
  cy.get('input[placeholder="Password"]').clear().type(clave, { log: false });
});

When("ingreso el usuario {string} con la contraseña de prueba", (usuario) => {
  const clave = Cypress.env("E2E_PASSWORD");
  expect(clave, "CYPRESS_E2E_PASSWORD definida").to.be.a("string").and.not.be.empty;
  cy.get('input[placeholder="Username"]').clear().type(usuario);
  cy.get('input[placeholder="Password"]').clear().type(clave, { log: false });
});

When("presiono el botón Login", () => {
  cy.contains("button", "Login").click();
});

Then("veo la página de administración", () => {
  cy.location("pathname", { timeout: 10000 }).should("eq", "/admin");
});

Then("sigo en la pantalla de login", () => {
  cy.wait("@login");
  cy.location("pathname").should("eq", "/login");
});

Then("veo un aviso que contiene {string}", (texto) => {
  cy.contains(texto, { timeout: 10000 }).should("be.visible");
});

// ---------- App real (escenarios @e2e) ----------

When("pido GET {string}", (ruta) => {
  cy.request({ url: ruta, failOnStatusCode: false }).as("respuesta");
});

Then("la respuesta tiene estado {int}", (estado) => {
  cy.get("@respuesta").its("status").should("eq", estado);
});

// The front end: one call to the API, which `flint openapi --typescript` can type.
const response = await fetch("/api/greetings/" + encodeURIComponent("visitor"));
document.getElementById("greeting").textContent = (await response.json()).text;

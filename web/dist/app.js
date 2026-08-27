const form = document.querySelector("#seal-form");
const receipt = document.querySelector(".receipt");

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const side = new FormData(form).get("side");
  const stake = document.querySelector("#stake").value;
  const salt = document.querySelector("#salt").value;
  // Practice-only feedback. Production commitments use ABI-packed keccak256.
  const bytes = new TextEncoder().encode(`41:local-demo:${side}:${salt}`);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const hash = `0x${[...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("")}`;

  receipt.classList.remove("sealed");
  requestAnimationFrame(() => {
    document.querySelector("#receipt-title").textContent = "PRACTICE CHECKSUM CREATED";
    document.querySelector("#receipt-side").textContent = "HIDDEN UNTIL REVEAL";
    document.querySelector("#receipt-stake").textContent = `${Number(stake).toFixed(2)} RITUAL`;
    document.querySelector("#receipt-hash").textContent = hash;
    receipt.classList.add("sealed");
  });
});

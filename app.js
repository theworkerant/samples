import css from "../css/app.scss"

import "phoenix_html"

import {Socket} from "phoenix"
import LiveSocket from "phoenix_live_view"

window.onload = function() {
  let timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;

  let evil_eye_mood = function() {
    let eye = document.getElementById("eye-white"),
      mood = document.getElementById("bargains").getAttribute("data-mood");

    if (eye && eye.childElementCount > 0 && mood !== "neutral") {
      eye.children[0].classList.remove("neutral");
      eye.children[0].classList.add(mood);
      setTimeout(() => {
        document.getElementById("eye-white").children[0].classList.remove(mood);
        document.getElementById("eye-white").children[0].classList.add("neutral");
      }, 500);
    }
  }

  let animate_evil_eye = function() {
    let backdrop1 = document.getElementById("evil-eye-backdrop1"),
      backdrop2 = document.getElementById("evil-eye-backdrop2"),
      eyelid = document.getElementById("eyelid"),
      rotation1 = document.getElementById("evil-eye-animation").getAttribute("data-rotation1"),
      rotation2 = document.getElementById("evil-eye-animation").getAttribute("data-rotation2"),
      blinking = document.getElementById("evil-eye-animation").getAttribute("data-blinking");

    if (backdrop1 && backdrop1.childElementCount > 0) {
      backdrop1.children[0].children[0].setAttribute("transform", `translate(0, 0) scale(1.5, 1) rotate(${rotation1} 0 0)`);
      backdrop2.children[0].children[0].setAttribute("transform", `translate(0, 0) scale(1, 1) rotate(${rotation2} 0 0)`);

      if (blinking === "true") {
        eyelid.classList.add("blinking");
        setTimeout(() => {
          document.getElementById("eyelid").classList.remove("blinking");
        }, 50);
      }
    }
  }

  let Hooks = {}
  Hooks.App = {
    updated() {
      setTimeout(evil_eye_mood, 500);
    }
  }
  Hooks.EvilEyeAnimation = {
    mounted() {
      setTimeout(animate_evil_eye, 500);
    },
    updated() {
      animate_evil_eye();
      document.getElementById("eyelid").classList.remove("blinking");
    }
  }
  Hooks.Signup = {
    updated() {
      let token = document.getElementById("signup").getAttribute("token");
      if (token) { location.href = `/session/token?token=${token}`; }
    }
  }

  let liveSocket = new LiveSocket("/live", Socket, {params: {timezone: timezone}, hooks: Hooks});
  liveSocket.connect();
}

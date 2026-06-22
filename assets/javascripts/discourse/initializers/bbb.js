import InsertBbbModal from "../components/modal/insert-bbb";
import { withPluginApi } from "discourse/lib/plugin-api";
import { iconHTML } from "discourse/lib/icon-library";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

function launchBBB(el) {
  const data = el.dataset;

  // Configuración: minutos antes de la hora programada para permitir acceso
  const minutesBefore = 10;

  // Si es un meeting programado, validar acceso (solo fecha de inicio, sin límite de duración)
  if (data.startdate && data.starttime) {
    const startDate = data.startdate;
    const startTime = data.starttime;

    try {
      const startDateTime = new Date(`${startDate} ${startTime} UTC`);
      const now = new Date();

      // Calcular tiempo permitido: hora programada menos minutesBefore
      const allowedTime = new Date(startDateTime.getTime() - (minutesBefore * 60000));

      if (now < allowedTime) {
        // Meeting no ha comenzado
        const startTimeStr = startDateTime.toLocaleString();
        alert(`The meeting has not started yet. (Starts: ${startTimeStr})`);
        return;
      }
      // Sin validación de fin - meetings sin límite de tiempo
    } catch (e) {
      console.error("Error parsing meeting date/time:", e);
    }
  }

  // Preparar datos para el backend
  const requestData = {};

  if (data.meetingid) {
    // Es un meeting existente - usar el meeting ID y passwords guardados
    requestData.meetingID = data.meetingid;
    requestData.attendeePW = data.attendeepw || '';
    requestData.moderatorPW = data.moderatorpw || '';
    requestData.mode = "existing";
  } else {
    // Fallback - crear nuevo meeting (modo legacy)
    requestData.mode = "new";
    requestData.meetingName = data.meetingname || "Discourse Meeting";
    requestData.startDate = data.startdate;
    requestData.startTime = data.starttime;
  }

  ajax("/bbb/create.json", {
    type: "POST",
    data: requestData,
  })
    .then((res) => {
      if (res.url) {
        // Always open in new window due to X-Frame-Options
        window.open(res.url, "_blank");
      } else if (res.error) {
        alert(res.error);
      }
    })
    .catch(function (error) {
      popupAjaxError(error);
    });
}

function attachButton(el) {
  const data = el.dataset;
  const meetingName = data.meetingname;
  const customLabel = data.label;

  let buttonLabel;
  if (customLabel) {
    buttonLabel = customLabel;
  } else if (meetingName) {
    buttonLabel = `Join Meeting: ${meetingName}`;
  } else {
    buttonLabel = i18n("bbb.launch");
  }

  el.innerHTML = `<button class='launch-bbb btn'>${iconHTML(
    "video"
  )} ${buttonLabel}</button>`;
  el.querySelector("button").addEventListener("click", () => launchBBB(el));
}

function attachStatus(el) {
  const status = el.querySelector(".bbb-status");
  const data = el.dataset;

  ajax(`/bbb/status/${data.meetingID}.json`).then((res) => {
    if (res.avatars) {
      status.innerHTML = `<span>On the call: </span>`;
      res.avatars.forEach(function (avatar) {
        const img = document.createElement("img");
        img.src = avatar.avatar_url;
        img.className = "avatar";
        img.width = 25;
        img.height = 25;
        img.title = avatar.name;
        status.appendChild(img);
      });
    }
  });
}

function attachBBB(element) {
  element.querySelectorAll("[data-wrap=discourse-bbb]").forEach((el) => {
    attachButton(el);
    const status = document.createElement("span");
    status.className = "bbb-status";
    el.appendChild(status);
    attachStatus(el);
  });
}

export default {
  name: "insert-bbb",

  initialize() {
    withPluginApi((api) => {
      const currentUser = api.getCurrentUser();
      const siteSettings = api.container.lookup("service:site-settings");

      api.decorateCookedElement(
        (element, helper) => {
          if (helper) {
            attachBBB(element);
          }
        },
        { id: "discourse-bbb" }
      );

      if (
        !siteSettings.bbb_staff_only ||
        (siteSettings.bbb_staff_only && currentUser && currentUser.staff)
      ) {
        api.addComposerToolbarPopupMenuOption({
          icon: "video",
          label: "bbb.composer_title",
          action: (toolbarEvent) => {
            api.container.lookup("service:modal").show(InsertBbbModal, {
              model: { toolbarEvent }
            });
          },
        });
      }
    });
  },
};

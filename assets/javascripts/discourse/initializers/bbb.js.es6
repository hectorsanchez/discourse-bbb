import InsertBbbModal from "../components/modal/insert-bbb";
import { withPluginApi } from "discourse/lib/plugin-api";
import { iconHTML } from "discourse-common/lib/icon-library";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

function launchBBB($elem) {
  const data = $elem.data();
  const site = Discourse.__container__.lookup("site:main");
  const capabilities = Discourse.__container__.lookup("capabilities:main");

  // Configuración: minutos antes de la hora programada para permitir acceso
  const minutesBefore = 5;

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

function attachButton($elem) {
  const data = $elem.data();
  const meetingName = data.meetingname || data.meetingName; // Puede venir como meetingname o meetingName
  const customLabel = data.label;
  
  let buttonLabel;
  if (customLabel) {
    buttonLabel = customLabel;
  } else if (meetingName) {
    buttonLabel = `Join Meeting: ${meetingName}`;
  } else {
    buttonLabel = I18n.t("bbb.launch");
  }
  
  $elem.html(
    `<button class='launch-bbb btn'>${iconHTML(
      "video"
    )} ${buttonLabel}</button>`
  );
  $elem.find("button").on("click", () => launchBBB($elem));
}

function attachStatus($elem, helper) {
  const status = $elem.find(".bbb-status");
  const data = $elem.data();

  ajax(`/bbb/status/${data.meetingID}.json`).then((res) => {
    if (res.avatars) {
      status.html(`<span>On the call: </span>`);
      res.avatars.forEach(function (avatar) {
        status.append(
          `<img src="${avatar.avatar_url}" class="avatar" width="25" height="25" title="${avatar.name}" />`
        );
      });
    }
  });
}

function attachBBB($elem, helper) {
  if (helper) {
    $elem.find("[data-wrap=discourse-bbb]").each((idx, val) => {
      attachButton($(val));
      $(val).append("<span class='bbb-status'></span>");
      attachStatus($(val), helper);
    });
  }
}

export default {
  name: "insert-bbb",

  initialize() {
    withPluginApi("1.13.0", (api) => {
      const currentUser = api.getCurrentUser();
      const siteSettings = api.container.lookup("site-settings:main");

      api.decorateCooked(attachBBB, {
        id: "discourse-bbb",
      });

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

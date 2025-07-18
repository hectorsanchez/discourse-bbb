import InsertBbbModal from "../components/modal/insert-bbb";
import { withPluginApi } from "discourse/lib/plugin-api";
import { iconHTML } from "discourse-common/lib/icon-library";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

function launchBBB($elem) {
  const data = $elem.data();
  const site = Discourse.__container__.lookup("site:main");
  const capabilities = Discourse.__container__.lookup("capabilities:main");

  ajax("/bbb/create.json", {
    type: "POST",
    data: data,
  })
    .then((res) => {
      if (res.url) {
        // Always open in new window due to X-Frame-Options
        window.open(res.url, "_blank");
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

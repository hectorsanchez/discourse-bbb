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
        if (
          capabilities.isAppWebview ||
          (site.mobileView && !data.mobileIframe) ||
          (!site.mobileView && !data.desktopIframe)
        ) {
          window.location.href = res.url;
        } else {
          $elem.children().hide();
          $elem.append(
            `<iframe src="${res.url}" allowfullscreen="true" allow="camera; microphone; fullscreen; speaker" width="100%" height="500" style="border:none"></iframe>`
          );
        }
      }
    })
    .catch(function (error) {
      popupAjaxError(error);
    });
}

function attachButton($elem) {
  const buttonLabel = $elem.data("label") || I18n.t("bbb.launch");

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
    console.log("BBB Plugin: Initializing...");
    
    withPluginApi("0.8.31", (api) => {
      console.log("BBB Plugin: Plugin API loaded");
      
      const currentUser = api.getCurrentUser();
      const siteSettings = api.container.lookup("site-settings:main");
      
      console.log("BBB Plugin: Current user:", currentUser);
      console.log("BBB Plugin: BBB enabled:", siteSettings.bbb_enabled);
      console.log("BBB Plugin: BBB staff only:", siteSettings.bbb_staff_only);
      console.log("BBB Plugin: User is staff:", currentUser && currentUser.staff);

      api.decorateCooked(attachBBB, {
        id: "discourse-bbb",
      });

      if (
        !siteSettings.bbb_staff_only ||
        (siteSettings.bbb_staff_only && currentUser && currentUser.staff)
      ) {
        console.log("BBB Plugin: Adding composer toolbar button");
        
        const toolbarAction = (toolbarEvent) => {
          console.log("BBB Plugin: *** TOOLBAR BUTTON CLICKED ***");
          console.log("BBB Plugin: toolbarEvent:", toolbarEvent);
          
          try {
            const modal = api.container.lookup("service:modal");
            console.log("BBB Plugin: Modal service found:", modal);
            
            modal.show("modal/insert-bbb", {
              model: {
                toolbarEvent,
              },
            });
            console.log("BBB Plugin: Modal.show called");
          } catch (error) {
            console.error("BBB Plugin: Error showing modal:", error);
            
            // Fallback: intentar con el método anterior
            try {
              console.log("BBB Plugin: Trying fallback modal method");
              const modalService = api.container.lookup("service:modal");
              modalService.show("insert-bbb", {
                model: {
                  toolbarEvent,
                },
              });
            } catch (fallbackError) {
              console.error("BBB Plugin: Fallback also failed:", fallbackError);
            }
          }
        };
        
        console.log("BBB Plugin: Toolbar action function created:", toolbarAction);
        
        api.addComposerToolbarPopupMenuOption({
          icon: "video",
          label: "bbb.composer_title",
          action: toolbarAction,
        });
        
        console.log("BBB Plugin: addComposerToolbarPopupMenuOption called");
      } else {
        console.log("BBB Plugin: Staff only mode enabled and user is not staff");
      }
    });
  },
};

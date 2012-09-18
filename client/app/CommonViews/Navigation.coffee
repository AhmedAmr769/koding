class NavigationController extends KDListViewController

  reset:->
    @removeAllItems()
    @instantiateListItems @getData().items

  selectItemByName:(name)->
    item = no
    for navItem in @itemsOrdered
      if navItem.name is name
        @selectItem item = navItem
        break
    item

  instantiateListItems:(items)->

    newItems = for itemData in items
      if KD.isLoggedIn()
        continue if itemData.loggedOut
      else
        continue if itemData.loggedIn
      @getListView().addItem itemData


class NavigationList extends KDListView

  itemClass:(options,data)->
    if data.title is "Invite Friends"
      new NavigationInviteLink options, data
    else
      super

class NavigationLink extends KDListItemView

  constructor:(options,data)->

    super options,data

    @name = data.title
    @setClass 'navigation-item clearfix'

  mouseDown:(event)->

    mc = @getSingleton('mainController')
    mc.emit "NavigationLinkTitleClick"
      orgEvent : event
      pageName : @getData().title
      appPath  : @getData().path or @getData().title
      navItem  : @

  partial:(data)->

    "<a class='title' href='#'><span class='main-nav-icon #{@utils.slugify data.title}'></span>#{data.title}</a>"

class AdminNavigationLink extends NavigationLink

  mouseDown:(event)->

    cb = @getData().callback
    cb.call @ if cb

class NavigationInviteLink extends NavigationLink

  constructor:->

    super

    @hide()
    @count = new KDCustomHTMLView
      pistachio: "{{#(quota)-#(usage)}}"

    @utils.wait 10000, =>
      KD.whoami().fetchLimit? 'invite', (err, limit)=>
        if limit?
          @show()
          @count.setData limit
          limit.on 'update', => @count.render()
          @count.render()

  sendInvite:(formData, modal)->

    bongo.api.JInvitation.create
      emails        : [formData.recipient]
      customMessage :
        # subject     : formData.subject
        body        : formData.body
    , (err)=>
      modal.modalTabs.forms["Invite Friends"].buttons.Send.hideLoader()
      if err
        new KDNotificationView
          title: err.message or 'Sorry, something bad happened.'
          content: 'Please try again later!'
      else
        new KDNotificationView title: 'Success!'
        modal.destroy()

  viewAppended:->

    @setTemplate @pistachio()
    @template.update()

  pistachio:->
    "<a class='title' href='#'><span class='main-nav-icon #{__utils.slugify @getData().title}'>{{> @count}}</span>#{@getData().title}</a>"


  # take this somewhere else
  # was a beta quick solution
  mouseDown:(event)->
    limit = @count.getData()
    if !limit? or limit.getAt('quota') - limit.getAt('usage') <= 0
      new KDNotificationView
        title   : 'You are temporarily out of invitations.'
        content : 'Please try again later.'
    else
      return if @modal
      @modal = modal = new KDModalViewWithForms
        title                   : "<span class='invite-icon'></span>Invite Friends to Koding"
        content                 : ""
        width                   : 500
        height                  : "auto"
        cssClass                : "invitation-modal"
        tabs                    :
          callback              : (formData)=>
            @sendInvite formData, modal
          forms                 :
            "Invite Friends"    :
              fields            :
                recipient       :
                  label         : "Send To:"
                  type          : "text"
                  name          : "recipient"
                  placeholder   : "Enter your friend's email address..."
                  validate      :
                    rules       :
                      required  : yes
                      email     : yes
                    messages    :
                      required  : "An email address is required!"
                      email     : "That does not not seem to be a valid email address!"
                # Subject         :
                #   label         : "Subject:"
                #   type          : "text"
                #   name          : "subject"
                #   placeholder   : "Come try Koding, a new way for developers to work..."
                #   defaultValue  : "Come try Koding, a new way for developers to work..."
                #   # attributes    :
                #   #   readonly    : yes
                Message         :
                  label         : "Message:"
                  type          : "textarea"
                  name          : "body"
                  placeholder   : "Hi! You're invited to try out Koding, a new way for developers to work."
                  defaultValue  : "Hi! You're invited to try out Koding, a new way for developers to work."
                  # attributes    :
                  #   readonly    : yes
              buttons           :
                Send            :
                  style         : "modal-clean-gray"
                  type          : 'submit'
                  loader        :
                    color       : "#444444"
                    diameter    : 12
                cancel          :
                  style         : "modal-cancel"
                  callback      : ()->
                    modal.destroy()

    @listenTo
      KDEventTypes       : "KDModalViewDestroyed"
      listenedToInstance : modal
      callback           : =>
        @modal = null

    inviteForm = modal.modalTabs.forms["Invite Friends"]
    inviteForm.on "FormValidationFailed", => inviteForm.buttons["Send"].hideLoader()

    modalHint = new KDView
      cssClass  : "modal-hint"
      partial   : "<p>Your friend will receive an Email from Koding that
                   includes a unique invite link so they can register for
                   the Koding Public Beta.</p>
                   <p><cite>* We take privacy seriously, we will not share any personal information.</cite></p>"

    modal.modalTabs.addSubView modalHint, null, yes

    inviteHint = new KDView
      cssClass  : "invite-hint fl"
      pistachio : "{{#(quota)-#(usage)}} Invites remaining"
    , @count.getData()

    modal.modalTabs.panes[0].form.buttonField.addSubView inviteHint, null, yes


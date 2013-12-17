class ActivityWidget extends KDView
  constructor: (options = {}, data) ->
    options.cssClass       = KD.utils.curry "status-update-widget", options.cssClass
    options.childOptions or= {}
    super options, data
    @activity = null

  showForm: (callback) ->
    @inputWidget?.show()
    @inputWidget.once "Submit", (err, activity) =>
      return  KD.showError err if err
      @addActivity activity  if activity
      callback err, activity

  hideForm: ->
    @inputWidget?.destroy()

  display: (id, callback = noop) ->
    KD.remote.cacheable "JNewStatusUpdate", id, (err, activity) =>
      KD.showError err
      callback err, activity
      @addActivity activity  if activity and not err

  create: (body, callback = noop) ->
    KD.remote.api.JNewStatusUpdate.create {body}, (err, activity) =>
      KD.showError err
      callback err, activity
      @addActivity activity  if activity and not err

  reply: (body, callback = noop) ->
    @activity?.reply body, callback

  addActivity: (activity) ->
    @activity = activity
    @addSubView new ActivityWidgetItem @getOptions().childOptions, activity

  viewAppended: ->
    {defaultValue} = @getOptions()
    KD.singleton("appManager").create "Activity", =>
      @addSubView @inputWidget = new ActivityInputWidget {defaultValue}

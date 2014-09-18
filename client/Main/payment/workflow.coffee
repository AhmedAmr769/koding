# This class is responsible of showing the payment modal.
# This workflow will decide if what to do next.
# No matter where you are instantiating this class,
# as long as you pass the view instance to this class
# it will emit necessary events when a substantial thing
# happens in the work flow.
#
# Necessary options when you instantiate it.
#
# planName   : string (see PaymentWorkflow.plans)
# monthPrice : int (e.g 1900 for $19)
# yearPrice  : int (e.g 19000 for $190)
# view       : KDView
class PaymentWorkflow extends KDController

  @interval:
    MONTH  : 'month'
    YEAR   : 'year'

  @plan          :
    FREE         : 'free'
    HOBBYIST     : 'hobbyist'
    DEVELOPER    : 'developer'
    PROFESSIONAL : 'professional'

  constructor: (options = {}, data) ->

    super options, data

    @start()
    @initPaymentProvider()


  initPaymentProvider: ->

    return  if window.Stripe?

    options = tagName: 'script', attributes: { src: 'https://js.stripe.com/v2/' }
    document.head.appendChild (@providerScript = new KDCustomHTMLView options).getElement()

    repeater = KD.utils.repeat 500, =>

      return  unless Stripe?

      Stripe.setPublishableKey('pk_test_6OB11qvDKuUlo71pFqd6nW9K')

      @modal.emit 'PaymentProviderLoaded', { provider: Stripe }
      window.clearInterval repeater


  start: ->

    { planName, monthPrice, yearPrice } = @getOptions()

    @modal = new PaymentModal state: { planName, monthPrice, yearPrice }
    @modal.on "PaymentSubmitted", (formData)->
      {
        cardNumber, cardCVC, cardMonth, cardYear, planName, planInterval
      } = formData

      Stripe.card.createToken
        number    : formData.cardNumber
        cvc       : formData.cardCVC
        exp_month : formData.cardMonth
        exp_year  : formData.cardYear
      , (status, response)->

        # handle valiation here
        if response.error
          return KDNotificationView title: "Invalid cc"

        token = response.id

        {paymentController} = KD.singletons
        paymentController.subscribe token, planName, planInterval, {email:"senthil@koding.com"}, ->
          console.log ">>>>>>>>>>> request from local", arguments...


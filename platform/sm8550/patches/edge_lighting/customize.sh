# Fix Edge lighting corner radius using the actual hardware model.
SET_PROP "system" "ro.factory.model" "$(GET_PROP "vendor" "ro.product.vendor.model")"

json.extract! user, :id, :name, :email
json.role "member"
json.profile do
  json.bio user.bio
end
